# encoding: UTF-8
require "date"

# Redmine plugin for Document Management System "Features"
#
# Copyright (C) 2011   Vít Jonáš <vit.jonas@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class HgpCmisController < ApplicationController
  include HgpCmisModule
  
  unloadable
  
  before_filter :find_project
  before_filter :except => [:delete_entries]
  before_filter :find_folder, :except => [:new, :create, :edit_root, :save_root]
  before_filter :find_parent, :only => [:new, :create]
  
  def show
    if session[:cmis_server_login].blank?
      redirect_to :action => "login", :id => @project
      return
    else
      # Si los datos de autenticación están en sesión, me aseguro de ponerlos en el helper de project_settings
      HgpCmisProjectSettings::server_login = session[:cmis_server_login]
      HgpCmisProjectSettings::server_password = session[:cmis_server_password]
    end
    begin
      cmis_connect(HgpCmisProjectSettings::get_project_params(@project))

      if @folder.nil?
        #@subfolders = HgpCmisFolder.project_root_folders(@project)  
        @subfolders = folders_in_path("/")
        @files = files_in_path("/")
      else 
        #@subfolders = @folder.subfolders
        @subfolders = folders_in_path(@folder.path)
        @files = files_in_path(@folder.path)
      end
      
      @files.sort! do |a,b|
        a.last_revision.title <=> b.last_revision.title
      end
      flash.discard
    rescue HgpCmisException=>e
      flash[:error] = l(:error_conexion_hgp_cmis)
      flash.keep # Para no perder el mensaje de error
      redirect_to :action => "login", :id => @project
    end
  end
  
  def login
    if params.keys.include?('cmis_server_password') && params.keys.include?('cmis_server_login') && !params['cmis_server_login'].blank? && !params['cmis_server_password'].blank?
      session[:cmis_server_login] = params['cmis_server_login']
      session[:cmis_server_password] = params['cmis_server_password']
      
      HgpCmisProjectSettings::server_login = params['cmis_server_login']
      HgpCmisProjectSettings::server_password = params['cmis_server_password']

      begin
        cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
        redirect_to :action => "show", :id => @project, :folder_path => @folder_path
      rescue HgpCmisException=>e
        flash[:error] = l(:error_conexion_hgp_cmis)
        flash.discard
        render :action => "login"
      end
      
    else
      #flash[:warning] = "Debe rellenar todos los campos"
    end    
  end
  

  def entries_operation
    selected_folders = params[:subfolders]
    selected_files = params[:files]
    
    if selected_folders.nil? && selected_files.nil?
      flash[:warning] = l(:warning_no_entries_selected)
      redirect_to :action => "show", :id => @project, :folder_path => @folder_path
      return
    end
    
    if !params[:email_entries].blank?
      email_entries(selected_folders, selected_files)
    else
      download_entries(selected_folders, selected_files)
    end
  rescue ZipMaxFilesError
    flash[:error] = l(:error_max_files_exceeded, :number => Setting.plugin_hgp_cmis["hgp_cmis_max_file_download"].to_i.to_s)
    redirect_to({:controller => "hgp_cmis", :action => "show", :id => @project, :folder_id => @folder})
  rescue EmailMaxFileSize
    flash[:error] = l(:error_max_email_filesize_exceeded, :number => Setting.plugin_hgp_cmis["hgp_cmis_max_email_filesize"].to_s)
    redirect_to({:controller => "hgp_cmis", :action => "show", :id => @project, :folder_id => @folder})
  rescue HgpCmisAccessError
    render_403
  end

  def entries_email
    @email_params = params[:email]
    if @email_params["to"].strip.blank?
      flash.now[:error] = l(:error_email_to_must_be_entered)
      render :action => "email_entries"
      return
    end
    HgpCmisMailer.deliver_send_documents(User.current, @email_params["to"], @email_params["cc"],
      @email_params["subject"], @email_params["zipped_content"], @email_params["body"])
    File.delete(@email_params["zipped_content"])
    flash[:notice] = l(:notice_email_sent)
    redirect_to({:controller => "hgp_cmis", :action => "show", :id => @project, :folder_id => @folder})
  end

  class ZipMaxFilesError < StandardError
  end

  class EmailMaxFileSize < StandardError
  end

  def delete_entries
    begin
      selected_folders = params[:subfolders]
      selected_files = params[:files]
      if selected_folders.nil? && selected_files.nil?
        flash[:warning] = l(:warning_no_entries_selected)
      else
        failed_entries = []
        deleted_files = []
        unless selected_folders.nil?
          if User.current.allowed_to?(:hgp_cmis_folder_manipulation, @project)
            selected_folders.each do |subfolderpath|
              delete_cmis_folder(subfolderpath)
            end
          else
            flash[:error] = l(:error_user_has_not_right_delete_folder)
          end
        end
        unless selected_files.nil?
          if User.current.allowed_to?(:hgp_cmis_file_manipulation, @project)
            selected_files.each do |fileid|
              delete_cmis_file(fileid)
            end
          elseasasa
            flash[:error] = l(:error_user_has_not_right_delete_file)
          end
        end
        unless deleted_files.empty?
          deleted_files.each {|f| log_activity(f, "deleted")}
          HgpCmisMailer.deliver_files_deleted(User.current, deleted_files)
        end
        if failed_entries.empty?
          flash[:notice] = l(:notice_entries_deleted)
        else
          flash[:warning] = l(:warning_some_entries_were_not_deleted, :entries => failed_entries.map{|e| e.title}.join(", "))
        end
      end
    rescue HgpCmisException=>e
      flash[:error] = e.message
    #rescue ActiveCMIS::Error::PermissionDenied
    rescue ActiveCMIS::HttpError::AuthenticationError
      flash[:error] = "NO FUNCIONAA!!!!"
    end
    redirect_to :controller => "hgp_cmis", :action => "show", :id => @project, :folder_path => @folder_path
  
  end

  # Folder manipulation

  def new
    @pathfolder = @parent
    @folder = HgpCmisFolder.new()
    render :action => "edit"
  end

  def create
    begin
      @folder = HgpCmisFolder.new(params.require(:hgp_cmis_folder).permit(:title))
      @folder.project = @project
      @folder.user = User.current
      @folder.title = @folder.title
      @folder.path = @parent_path + "/" + @folder.title
      
      if @folder.save
        flash[:notice] = l(:notice_folder_created)
        redirect_to({:controller => "hgp_cmis", :action => "show", :id => @project, :folder_path => @folder.path,
          :alfresco_uuid => @folder.alfresco_uuid})
      else
        @pathfolder = @parent
        render :action => "edit"
      end
    rescue HgpCmisException=>e
      flash[:error] = e.message
      flash.discard
      @pathfolder = @parent
      render :action => "edit"
    rescue ActiveCMIS::Error::PermissionDenied
      flash[:error] = l(:hgp_cmis_permission_denied)
      flash.discard
      @pathfolder = @parent
      render :action => "edit"
    end
  end

  def edit
    @parent = @folder.folder
    @pathfolder = copy_folder(@folder)
  end

  def save
    begin
      unless params[:hgp_cmis_folder]
        redirect_to :controller => "hgp_cmis", :action => "show", :id => @project, :folder_id => @folder
        return
      end
      @pathfolder = copy_folder(@folder)
      @folder.attributes = params[:hgp_cmis_folder]
      if @folder.save
        flash[:notice] = l(:notice_folder_details_were_saved)
        redirect_to :controller => "hgp_cmis", :action => "show", :id => @project, :folder_id => @folder
      else
        render :action => "edit"
      end
    rescue HgpCmisException=>e
      flash[:error] = e.message
      flash.discard
      render :action => "edit"
    rescue ActiveCMIS::Error::PermissionDenied
      flash[:error] = l(:hgp_cmis_permission_denied)
      flash.discard
      render :action => "edit"
    end
  end

  def delete
    begin
      #check_project(@delete_folder = HgpCmisFolder.find(params[:delete_folder_id]))
      delete_folder_path = params[:delete_folder_path]
      delete_cmis_folder(delete_folder_path)
      flash[:notice] = l(:notice_folder_deleted)      
    rescue HgpCmisException=>e
      flash[:error] = e.message
    rescue ActiveCMIS::Error::PermissionDenied
      flash[:error] = l(:hgp_cmis_permission_denied)
    end
    redirect_to :controller => "hgp_cmis", :action => "show", :id => @project, :folder_path => get_path_to_folder(delete_folder_path)
  rescue HgpCmisAccessError
    render_403  
  end

  def edit_root
  end

  def save_root
    @project.hgp_cmis_description = params[:project][:hgp_cmis_description]
    @project.save!
    flash[:notice] = l(:notice_folder_details_were_saved)
    redirect_to :controller => "hgp_cmis", :action => "show", :id => @project
  end

  def notify_activate
    if @folder.notification
      flash[:warning] = l(:warning_folder_notifications_already_activated)
    else
      @folder.notify_activate
      flash[:notice] = l(:notice_folder_notifications_activated)
    end
    redirect_to params[:current] ? params[:current] : 
      {:controller => "hgp_cmis", :action => "show", :id => @project, :folder_id => @folder.folder}
  end
  
  def notify_deactivate
    if !@folder.notification
      flash[:warning] = l(:warning_folder_notifications_already_deactivated)
    else
      @folder.notify_deactivate
      flash[:notice] = l(:notice_folder_notifications_deactivated)
    end
    redirect_to params[:current] ? params[:current] : 
      {:controller => "hgp_cmis", :action => "show", :id => @project, :folder_id => @folder.folder}
  end
  
  def approve_file
    file = HgpCmisFile.find(params[:file_id])
    revision = file.last_revision
    
    # Guardo el fichero en el repositorio CMIS
    file_content = File.new(revision.disk_file, "rb")
    revision.tempfile_path = revision.disk_file
    revision.workflow = 2
    
    begin
      revision.copy_file_content(file_content)      
      # Si todo ha ido bien, guardo el fichero con el workflow aprobado, y elimino la versión del disco      
      File.delete(revision.disk_file) if File.exist?(revision.disk_file)
      revision.save
      
      flash[:notice] = l(:notice_document_approved)
      
    rescue HgpCmisException=>e
      revision.workflow = 1
      flash[:error] = e.message
    rescue ActiveCMIS::Error::PermissionDenied
      revision.workflow = 1
      flash[:error] = l(:hgp_cmis_permission_denied)
    end
    
    redirect_to :controller => "hgp_cmis", :action => "show", :id => @project, :folder_path => params[:folder_path]
  end
  
  # Recuperación de carpetas/documentos a partir de un PATH
  def folders_in_path(path)
    res = []
    begin
      cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
      repositoryFolders = get_folders_in_folder(path)
      repositoryFolders.each{|repositoryFold| 
        newFold = map_repository_folder_to_redmine_folder(repositoryFold, path)
        res.push(newFold)
      }
      res.sort! { |a,b| a.title.downcase <=> b.title.downcase }
    rescue HgpCmisException=>e
      flash[:error] = e.message
    rescue ActiveCMIS::Error::PermissionDenied
      flash[:error] = l(:hgp_cmis_permission_denied)
    end
    return res
  end
  
  def files_in_path(path)
    res = []
    if User.current.allowed_to?(:view_hgp_cmis_files, @project)
      begin
        cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
        repositoryDocuments = get_documents_in_folder(path)
        repositoryDocuments.each{|repositoryDoc| 
          newDoc = map_repository_doc_to_redmine_file(repositoryDoc, path)
          res.push(newDoc)
        }

        # Archivos temporales
        tempFiles = HgpCmisFile.includes(:revisions).where(hgp_cmis_file_revisions: {workflow:1}).where(hgp_cmis_file_revisions: {path: @folder_path})

        tempFiles.each{|tempFile|
          res.push(tempFile)
        }
        
        res.sort! { |a,b| a.title.downcase <=> b.title.downcase }
      rescue HgpCmisException=>e
        flash[:error] = e.message
      rescue ActiveCMIS::Error::PermissionDenied
        flash[:error] = l(:hgp_cmis_permission_denied)
      end
    end
    return res
  end
  
  def delete_cmis_folder(path)
    cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
    remove_folder(path)
  end
  
  def delete_cmis_file(id)
    # Si el id tiene una barra, entonces es un path
    if (id.include?"/")
      cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
      remove_document(id)      
    else
      
      file = HgpCmisFile.find(id)
      if !file.nil?
        file.delete
      end
    end
  end
  
  # Synchronization
  # Syncs new folders from HGP_CMIS repository
  def synchronize_repository_changes
    show
    synchronize_folders
    synchronize_files
    render :partial => 'items'
  end
  
  def synchronize_folders
    check_new_folders
    check_deleted_folders
    @subfolders.sort! { |a,b| a.title.downcase <=> b.title.downcase }    
  end
  
  def check_new_folders
    begin      
      path = current_folder_path
      cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
      repositoryFolders = get_folders_in_folder(path)
      repositoryFolders.each{|repositoryFold|
        # Check if the folder is not mapped on redmine
        if !(@subfolders.detect{|folder| folder.title == repositoryFold.cmis.name}) 
          newFold = map_repository_folder_to_redmine_folder(repositoryFold, path)
          newFold.save
          @subfolders.push(newFold)
        end
      }
    
    rescue HgpCmisException=>e
      flash[:error] = e.message
      flash.discard
    rescue ActiveCMIS::Error::PermissionDenied
      flash[:error] = l(:hgp_cmis_permission_denied)
      flash.discard
    end
  end
  
  def check_deleted_folders    
    begin
      cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
      @subfolders.each{|folder|
        repositoryFolder = get_folder(folder.path)
        if (!repositoryFolder)
          # The folder has been deleted/moved
          folder.dirty = true
        end
      }
    rescue HgpCmisException=>e
      flash[:error] = e.message
      flash.discard
    end
  end
  
  def synchronize_folder
    folder = HgpCmisFolder.where(hgp_cmis_folder_id: params[:subfolder_id])
     begin
      cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
      repositoryFolder = get_folder(folder.path)
      
      if (!repositoryFolder)
        # Document deleted on HGP_CMIS ECM     
        folder.destroy
        folder = nil      
      end      
      
    rescue HgpCmisException=>e
      flash[:error] = e.message
      flash.discard
    rescue ActiveCMIS::Error::PermissionDenied
      flash[:error] = l(:hgp_cmis_permission_denied)
      flash.discard
    end
        
    render :partial => 'subfolder', :locals => {:subfolder => folder}    
  end
  
  def synchronize_files
    check_new_files
    check_changed_files
    @files.sort! { |a,b| a.title.downcase <=> b.title.downcase }
  end
  
  def check_new_files
    begin      
      path = current_folder_path
      cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
      repositoryFiles = get_documents_in_folder(path)
      repositoryFiles.each{|repositoryDoc|
        # Check if the document is not mapped on redmine
        if !(@files.detect{|doc| doc.last_revision.workflow == 2 && doc.last_revision.disk_filename == repositoryDoc.cmis.name}) 
          newFile = map_repository_doc_to_redmine_file(repositoryDoc)
          if (newFile.save)
            newRevision = map_repository_doc_to_redmine_revision(repositoryDoc, newFile)
            newRevision.save
            newFile.revisions = [newRevision]
            @files.push(newFile)
          end
        end
      }
    
    rescue HgpCmisException=>e
      flash[:error] = e.message
      flash.discard
    rescue ActiveCMIS::Error::PermissionDenied
      flash[:error] = l(:hgp_cmis_permission_denied)
      flash.discard
    end
  end
  
  def check_changed_files
    begin
      cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
      @files.each{|file|
        # Solo busco si el archivo está aprobado (ya está en Alfresco)
        if (file.last_revision.workflow == 2)
          repositoryDocument = get_document(file.last_revision.path)
          if (!repositoryDocument)
            # Document deleted on HGP_CMIS ECM
            file.dirty = true
          else
            # Check update date
            redmineTime = file.last_revision.updated_at
            redmineDate = DateTime.parse(redmineTime.to_s)
            
            repositoryDate = repositoryDocument.cmis.lastModificationDate
            repositoryTime = Time.parse(repositoryDate.to_s)
            
            diffInSeconds = repositoryDate - redmineDate
            diffInSeconds *= 1.days
            
            if (diffInSeconds > 60)
              file.dirty = true
            end
          end
        end
      }
    rescue HgpCmisException=>e
      flash[:error] = e.message
      flash.discard
    end
  end
  
  def synchronize_file
    
    file = HgpCmisFile.find(params[:file_id])    
    begin
      cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
      repositoryDocument = get_document(file.last_revision.path)
      
      if (!repositoryDocument)
        # Document deleted on HGP_CMIS ECM    
        file.destroy
        file = nil
        
      else
        # Updated                
        revision = file.last_revision
        revision.size = repositoryDocument.cmis.contentStreamLength
        revision.save
        file.reload
      end      
      
    rescue HgpCmisException=>e
      flash[:error] = e.message
      flash.discard
    rescue ActiveCMIS::Error::PermissionDenied
      flash[:error] = l(:hgp_cmis_permission_denied)
      flash.discard
    end
    
    render :partial => 'file', :locals => {:file => file}    
  end

  private

  def log_activity(file, action)
    Rails.logger.info "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{User.current.login}@#{request.remote_ip}/#{request.env['HTTP_X_FORWARDED_FOR']}: #{action} hgp_cmis://#{file.project.identifier}/#{file.id}"
  end

  def email_entries(selected_folders, selected_files)
    zip = HgpCmisZip.new
    zip_entries(zip, selected_folders, selected_files)
    
    ziped_content = "#{HgpCmisHelper.temp_dir}/#{HgpCmisHelper.temp_filename("hgp_cmis_email_sent_documents.zip")}";
    
    File.open(ziped_content, "wb") do |f|
      zip_file = File.open(zip.finish, "rb")
      while (buffer = zip_file.read(8192))
        f.write(buffer)
      end
    end

    max_filesize = Setting.plugin_hgp_cmis["hgp_cmis_max_email_filesize"].to_f
    if max_filesize > 0 && File.size(ziped_content) > max_filesize * 1048576
      raise EmailMaxFileSize
    end
    
    zip.files.each do |f| 
      log_activity(f,"emailing zip")
      audit = HgpCmisFileRevisionAccess.new(:user_id => User.current.id, :hgp_cmis_file_revision_id => f.last_revision.id, 
        :action => HgpCmisFileRevisionAccess::EmailAction)
      audit.save!
    end
    
    @email_params = {"zipped_content" => ziped_content}
    render :action => "email_entries"
  ensure
    zip.close unless zip.nil? 
  end

  def download_entries(selected_folders, selected_files)
    zip = HgpCmisZip.new
    zip_entries(zip, selected_folders, selected_files)
    
    zip.files.each do |f| 
      log_activity(f,"download zip")
      audit = HgpCmisFileRevisionAccess.new(:user_id => User.current.id, :hgp_cmis_file_revision_id => f.last_revision.id, 
        :action => HgpCmisFileRevisionAccess::DownloadAction)
      audit.save!
    end
    
    send_file(zip.finish, 
      :filename => filename_for_content_disposition(@project.name + "-" + DateTime.now.strftime("%y%m%d%H%M%S") + ".zip"),
      :type => "application/zip", 
      :disposition => "attachment")
  ensure
    zip.close unless zip.nil? 
  end
  
  def zip_entries(zip, selected_folders, selected_files)
    if selected_folders && selected_folders.is_a?(Array)
      selected_folders.each do |selected_folder_id|
        
        check_project(folder = HgpCmisFolder.find(selected_folder_id))
        zip.add_folder(folder, (@folder.hgp_cmis_path_str unless @folder.nil?)) unless folder.nil?
      end
    end
    if selected_files && selected_files.is_a?(Array)
      selected_files.each do |selected_file_id|
        
        check_project(file = HgpCmisFile.find(selected_file_id))
        zip.add_file(file, (@folder.hgp_cmis_path_str unless @folder.nil?)) unless file.nil?
      end
    end
    
    max_files = 0
    max_files = Setting.plugin_hgp_cmis["hgp_cmis_max_file_download"].to_i
    if max_files > 0 && zip.files.length > max_files
      raise ZipMaxFilesError, zip.files.length
    end
    
    zip
  end
  
  def find_project
    @project = Project.find(params[:id])
  end
  
  def find_folder
    @folder_path = ""
    if params.keys.include?("folder_path") && params[:folder_path] != nil && params[:folder_path] != ""
      begin
        cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
        repository_folder = get_folder(params[:folder_path])
        if repository_folder == nil
          repository_folder = get_folder_by_key(params[:alfresco_uuid])
        end

        @folder = map_repository_folder_to_redmine_folder(repository_folder, get_path_to_folder(params[:folder_path]))
        @folder.project = @project
        @folder_path = @folder.path
        @folder_uuid = repository_folder.key
        
        @hgp_cmis_path = @folder.hgp_cmis_path

      rescue HgpCmisException=>e
        flash[:error] = e.message
        flash.discard
      rescue ActiveCMIS::Error::PermissionDenied
        flash[:error] = l(:hgp_cmis_permission_denied)
        flash.discard
      end
    end
    #check_project(@folder)
  rescue HgpCmisAccessError
    render_403
  end

  def find_parent
    @parent_path = ""
    if params.keys.include?("parent_path") && params[:parent_path] != nil && params[:parent_path] != ""
      begin
        cmis_connect(HgpCmisProjectSettings::get_project_params(@project))
        repository_folder = get_folder(params[:parent_path])
        if repository_folder == nil
          repository_folder = get_folder_by_key(params[:alfresco_uuid])
        end
        
        @parent = map_repository_folder_to_redmine_folder(repository_folder, get_path_to_folder(params[:parent_path]))
        @parent_path = @parent.path
        # La visibilidad de las carpetas se basa en el sistema de permisos de Alfresco
        #check_project(@parent)
        rescue HgpCmisException=>e
          flash[:error] = e.message
          flash.discard
        rescue ActiveCMIS::Error::PermissionDenied
          flash[:error] = l(:hgp_cmis_permission_denied)
          flash.discard
       end
    end     
  rescue HgpCmisAccessError
    render_403
  end

  def check_project(entry)
    if !entry.nil? && entry.project != @project
      raise HgpCmisAccessError, l(:error_entry_project_does_not_match_current_project) 
    end
  end

  def copy_folder(folder)
    copy = folder.clone
    copy.id = folder.id
    copy
  end

end


