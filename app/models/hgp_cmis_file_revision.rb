# encoding: UTF-8
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

require 'active_cmis' 

class HgpCmisFileRevision < ActiveRecord::Base
  
  include HgpCmisModule
  
  unloadable
  belongs_to :file, :class_name => "HgpCmisFile", :foreign_key => "hgp_cmis_file_id"
  belongs_to :source_revision, :class_name => "HgpCmisFileRevision", :foreign_key => "source_hgp_cmis_file_revision_id"
  belongs_to :user
  belongs_to :folder, :class_name => "HgpCmisFolder", :foreign_key => "hgp_cmis_folder_id"
  belongs_to :deleted_by_user, :class_name => "User", :foreign_key => "deleted_by_user_id"
  belongs_to :project
  
  acts_as_event :title => Proc.new {|o| "#{l(:label_hgp_cmis_updated)}: #{o.file.hgp_cmis_path_str}"},
                :url => Proc.new {|o| {:controller => 'hgp_cmis_files', :action => 'show', :id => o.file}},
                :datetime => Proc.new {|o| o.updated_at },
                :description => Proc.new {|o| o.comment },
                :author => Proc.new {|o| o.user }
  
  acts_as_activity_provider :type => "hgp_cmis_files",
                            :timestamp => "#{HgpCmisFileRevision.table_name}.updated_at",
                            :author_key => "#{HgpCmisFileRevision.table_name}.user_id",
                            :permission => :view_hgp_cmis_files,
                            :scope => select("#{HgpCmisFileRevision.table_name}.*"). 
                                      joins("INNER JOIN #{HgpCmisFile.table_name} ON #{HgpCmisFileRevision.table_name}.hgp_cmis_file_id = #{HgpCmisFile.table_name}.id " +
                                             "INNER JOIN #{Project.table_name} ON #{HgpCmisFile.table_name}.project_id = #{Project.table_name}.id").
                                      where("#{HgpCmisFile.table_name}.deleted" => false)

  validates_presence_of :title
  validates_presence_of :name
  validates_format_of :name, :with => HgpCmisFolder.invalid_characters,
    :message => l(:error_contains_invalid_character)
  
  def before_create    
    self.major_version = 1
    self.minor_version = 0
  end
  
  def self.remove_extension(filename)
    filename[0, (filename.length - File.extname(filename).length)]
  end
  
  #TODO: check if better to move to hgp_cmis_upload class
  def self.filename_to_title(filename)
    remove_extension(filename).gsub(/_+/, " ");
  end
  
  def delete(delete_all = false)    
    dependent = HgpCmisFileRevision.where(source_hgp_cmis_file_revision_id: self.id, deleted: false)
    dependent.each do |d| 
      d.source_revision = self.source_revision
      d.save!
    end
    dependent = HgpCmisFileRevision.where(disk_filename: self.disk_filename)
    # Elimino de disco o Alfresco dependiendo del workflow
    if (self.workflow == 1)
      File.delete(self.disk_file) if dependent.length <= 1 && File.exist?(self.disk_file)
    else
      begin
        if (self.path != nil)
          cmis_connect(HgpCmisProjectSettings::get_project_params(project))
          puts "*****"
          puts self.path
          puts "*****"
          remove_document(self.path)
        end
      rescue HgpCmisException=>e
        raise e
      rescue ActiveCMIS::Error::PermissionDenied=>e
        raise e
      rescue Errno::ECONNREFUSED=>e
        self.path = nil
        raise HgpCmisException.new, l(:unable_connect_hgp_cmis)
      end
    end
    HgpCmisFileRevisionAccess.where(hgp_cmis_file_revision_id: self.id).each {|a| a.destroy}
    self.destroy    
  end
  
  def self.access_grouped(revision_id)
    sql = "select user_id, count(*) as count, min(created_at) as min, max(created_at) as max from #{HgpCmisFileRevisionAccess.table_name} where hgp_cmis_file_revision_id = ? group by user_id"
    self.connection.select_all(self.sanitize_sql_array([sql, revision_id]))
  end
  
  def access_grouped
    HgpCmisFileRevision.access_grouped(self.id)
  end
  
  def version
    "#{self.major_version}.#{self.minor_version}"
  end
  
  def disk_file
    "#{HgpCmisFile.storage_path}/#{self.disk_filename}"
  end
  
  def detect_content_type
    content_type = self.mime_type
    content_type = Redmine::MimeType.of(self.disk_filename) if content_type.blank?
    content_type = "application/octet-stream" if content_type.blank?
    content_type.to_s
  end
  
  #TODO: use standard clone method
  def clone
    new_revision = HgpCmisFileRevision.new
    new_revision.file = self.file
    new_revision.project = self.project
    new_revision.disk_filename = self.disk_filename
    new_revision.size = self.size
    new_revision.mime_type = self.mime_type
    new_revision.title = self.title
    new_revision.description = self.description
    new_revision.workflow = self.workflow
    new_revision.major_version = self.major_version
    new_revision.minor_version = self.minor_version
    
    new_revision.source_revision = self
    new_revision.user = User.current
    
    new_revision.name = self.name
    new_revision.folder = self.folder
    
    return new_revision
  end
  
  #TODO: validate if it isn't doubled or move it to view
  def workflow_str
    case workflow
      when 1 then l(:title_waiting_for_approval)
      when 2 then l(:title_approved)
    else nil
    end
  end
  
  def set_workflow(workflow)
    if User.current.allowed_to?(:hgp_cmis_file_approval, self.file.project)
      self.workflow = workflow
    else
      if self.source_revision.nil?
        self.workflow = workflow == 2 ? 1 : workflow
      else
        if workflow == 2 || self.source_revision.workflow == 1 || self.source_revision.workflow == 2
          self.workflow = 1
        else
          self.workflow = workflow
        end
      end
    end
  end
  
  def increase_version(version_to_increase, new_content)
    if new_content
      self.minor_version = case version_to_increase 
        when 2 then 0
      else self.minor_version + 1
      end
    else
      self.minor_version = case version_to_increase 
        when 1 then self.minor_version + 1
        when 2 then 0
      else self.minor_version
      end
    end
    
    self.major_version = case version_to_increase 
      when 2 then self.major_version + 1
    else self.major_version
    end
  end
  
  def display_title
    #if self.title.length > 35
    #  return self.title[0, 30] + "..."
    #else 
    return self.title
    #end
  end
  
  def new_storage_filename
    raise HgpCmisAccessError, "File id is not set" unless self.file.id
    filename = HgpCmisHelper.sanitize_filename(self.name)
    timestamp = DateTime.now.strftime("%y%m%d%H%M%S")
    while File.exist?(File.join(HgpCmisFile.storage_path, "#{timestamp}_#{self.file.id}_#{filename}"))
      timestamp.succ!
    end
    "#{timestamp}_#{self.file.id}_#{filename}"
  end
  
  def copy_file_content(open_file)
    # Dependiendo del workflow elegido, guardo en disco o en Alfresco directamente
    if (self.workflow == 1)
      File.open(self.disk_file, "wb") do |f| 
        while (buffer = open_file.read(8192))
          f.write(buffer)
        end
      end
    else
      begin
        cmis_connect(HgpCmisProjectSettings::get_project_params(project))
        save_document(path, name, get_stream_content(@tempfile_path))
      rescue HgpCmisException=>e
        self.path = nil
        save
        raise e
      rescue ActiveCMIS::Error::PermissionDenied=>e
        self.path = nil
        save
        raise e
      rescue Errno::ECONNREFUSED=>e
        self.path = nil
        save
        raise HgpCmisException.new, l(:unable_connect_hgp_cmis)
      end
    end
  end
  
  def tempfile_path=(path)
    @tempfile_path = path
  end
  
  def file_path
    return File.dirname(self.path)
  end
  
  def file_name
    return File.basename(self.path)
  end
  
  def hgp_cmis_file
    begin
      cmis_connect(HgpCmisProjectSettings::get_project_params(project))
      return read_document(self.path)
    rescue HgpCmisException=>e
      raise e
    rescue ActiveCMIS::Error::PermissionDenied=>e
      raise e
    rescue Errno::ECONNREFUSED=>e
      raise HgpCmisException.new, l(:unable_connect_hgp_cmis)  
    rescue =>e
      raise HgpCmisException.new, e.message
    end
  end
  
  def update_path(newPath)
    self.path = compose_path(newPath, substring_after_last(self.path, "/"))
    self.save
  end
  
end
