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

require 'redmine'

require_dependency 'hgp_cmis_hooks'

Redmine::Plugin.register :hgp_cmis do
  name "Cmis"
  author "Junta de Andalucía"
  description "Document Management CMIS integrated"
  version "1.0"
  url "http://www.juntadeandalucia.es"
  author_url "http://www.juntadeandalucia.es"
  
  requires_redmine :version_or_higher => '1.1.0'
  
  settings  :partial => 'settings/hgp_cmis_settings',
            :default => {
              "hgp_cmis_max_file_upload" => "0",
              "hgp_cmis_max_file_download" => "0",
              "hgp_cmis_max_email_filesize" => "0",
              "hgp_cmis_storage_directory" => "#{Rails.root}/files/hgp_cmis",
              "hgp_cmis_really_delete_files" => true,
              "hgp_cmis_zip_encoding" => "utf-8",
              "hgp_cmis_index_database" => "#{Rails.root}/files/hgp_cmis_index",
              "hgp_cmis_stemming_lang" => "english",
              "hgp_cmis_stemming_strategy" => "STEM_NONE",
              'server_url' => 'http://localhost:8080/alfresco/service/cmis',
              'repository_id' => 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
              'server_login' => 'user',
              'server_password' => 'password',
              'documents_path_base' => 'REDMINE'
            }
  
  menu :project_menu, :hgp_cmis, { :controller => "hgp_cmis", :action => "show" }, :caption => :menu_hgp_cmis, :before => :documents, :param => :id
  #delete_menu_item :project_menu, :documents
  
  activity_provider :hgp_cmis_files, :class_name => "HgpCmisFileRevision", :default => true

  project_module :hgp_cmis do
    permission :view_hgp_cmis_folders, {:hgp_cmis => [:show, :synchronize_repository_changes, :synchronize_folder, :synchronize_file, :login], :hgp_cmis_folders_copy => [:new, :copy_to, :move_to]}
    permission :hgp_cmis_user_preferences, {:hgp_cmis_state => [:user_pref_save]}
    permission :view_hgp_cmis_files, {:hgp_cmis => [:entries_operation, :entries_email],
      :hgp_cmis_files => [:show], :hgp_cmis_files_copy => [:new, :create, :move]}
    permission :hgp_cmis_folder_manipulation, {:hgp_cmis => [:new, :create, :delete, :edit, :save, :edit_root, :save_root]}
    permission :hgp_cmis_file_manipulation, {:hgp_cmis_files => [:create_revision, :delete, :lock, :unlock], :hgp_cmis_upload => [:upload_files, :upload_file, :commit_files]}
    permission :hgp_cmis_file_approval, {:hgp_cmis_files => [:delete_revision, :notify_activate, :notify_deactivate], 
      :hgp_cmis => [:notify_activate, :notify_deactivate, :approve_file]}
    permission :hgp_cmis_create_temp_files, {:hgp_cmis_files => [:create_revision, :delete, :delete_revision], :hgp_cmis_upload => [:upload_files, :upload_file, :commit_files]}
    #permission :force_file_unlock, {}
  end

  Redmine::WikiFormatting::Macros.register do
    desc "Wiki link to HGP_CMIS file:\n\n" +
             "!{{hgp_cmis(file_id [, title [, revision_id]])}}\n\n" +
         "_file_id_ / _revision_id_ can be found in link for file/revision download."
         
    macro :hgp_cmis do |obj, args|
      return nil if args.length < 1 # require file id
      entry_id = args[0].strip
      entry = HgpCmisFile.find(entry_id)
      unless entry.nil? || entry.deleted
        title = args[1] ? args[1] : entry.title
        revision = args[2] ? args[2] : ""
        return link_to "#{title}", :controller => "hgp_cmis_files", :action => "show", :id => entry, :download => revision
      end
      nil
    end
  end
  
  Redmine::WikiFormatting::Macros.register do
    desc "Wiki link to HGP_CMIS folder:\n\n" +
             "!{{hgp_cmisf(folder_id [, title])}}\n\n" +
         "_folder_id_ may be missing. _folder_id_ can be found in link for folder opening."
         
    macro :hgp_cmisf do |obj, args|
      if args.length < 1
        return link_to l(:link_documents), :controller => "hgp_cmis", :action => "show", :id => @project
      else
        entry_id = args[0].strip
        entry = HgpCmisFolder.find(entry_id)
        unless entry.nil?
          title = args[1] ? args[1] : entry.title
          return link_to "#{title}", :controller => "hgp_cmis", :action => "show", :id => entry.project, :folder_id => entry
        end
      end
      nil
    end
  end
  
end

Redmine::Search.map do |search|
  search.register :hgp_cmis_files
  search.register :hgp_cmis_folders
end
