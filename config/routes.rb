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

RedmineApp::Application.routes.draw do
  get 'hgp_cmis', to: 'hgp_cmis'
  get 'hgp_cmis_files', to: 'hgp_cmis_files#show'
  get 'hgp_cmis_show', to: 'hgp_cmis#show'
  post 'hgp_cmis_show', to: 'hgp_cmis#show'
  get 'hgp_cmis_state_user_pref_save', to: 'hgp_cmis_state#user_pref_save'
  patch 'hgp_cmis_state_user_pref_save', to: 'hgp_cmis_state#user_pref_save'
  get 'hgp_cmis_login', to: 'hgp_cmis#login'
  post 'hgp_cmis_login', to: 'hgp_cmis#login'
  get 'hgp_cmis_edit_root', to: 'hgp_cmis#edit_root'
  get 'hgp_cmis_edit_new', to: 'hgp_cmis#new'
  get 'hgp_cmis_entries_operation', to: 'hgp_cmis#entries_operation'
  get 'hgp_cmis_delete_entries', to: 'hgp_cmis#delete_entries'
  post 'hgp_cmis_delete_entries', to: 'hgp_cmis#delete_entries'
  get 'hgp_cmis_upload_upload_files', to: 'hgp_cmis_upload#upload_files'
  post 'hgp_cmis_upload_upload_files', to: 'hgp_cmis_upload#upload_files' 
  get 'hgp_cmis_upload_upload_file', to: 'hgp_cmis_upload#upload_file'
  post 'hgp_cmis_upload_upload_file', to: 'hgp_cmis_upload#upload_file'
  get 'hgp_cmis_notify_activate', to: 'hgp_cmis#notify_activate'
  get 'hgp_cmis_edit', to: 'hgp_cmis#edit'
  get 'hgp_cmis_delete', to: 'hgp_cmis#delete'
  post 'hgp_cmis_delete', to: 'hgp_cmis#delete'
  get 'hgp_cmis_folders_copy_new', to: 'hgp_cmis_folders_copy#new'
  get 'hgp_cmis_create', to: 'hgp_cmis#create'
  post 'hgp_cmis_create', to: 'hgp_cmis#create'
  get 'hgp_cmis_upload_commit_files', to: 'hgp_cmis_upload#commit_files'
  post 'hgp_cmis_upload_commit_files', to: 'hgp_cmis_upload#commit_files'
  get 'hgp_cmis_files_show', to:'hgp_cmis_files#show'
  get 'hgp_cmis_files_delete', to: 'hgp_cmis_files#delete'
  post 'hgp_cmis_files_delete', to: 'hgp_cmis_files#delete'
  get 'hgp_cmis_approve_file', to: 'hgp_cmis#approve_file'
  post 'hgp_cmis_approve_file', to: 'hgp_cmis#approve_file'
end
