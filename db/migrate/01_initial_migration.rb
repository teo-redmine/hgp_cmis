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

class InitialMigration < ActiveRecord::Migration
  def self.up
    create_table :hgp_cmis_folders do |t|
      t.references :project, :null => false
      t.references :hgp_cmis_folder
      
      t.string :title, :null => false
      t.text :description
      t.text :path
      t.boolean :dirty
      
      t.boolean :notification, :default => false, :null => false
      
      t.references :user, :null => false
      t.timestamps      
    end
    
    create_table :hgp_cmis_files do |t|
      t.references :project, :null => false
      
      # This two fileds are copy from last revision due to simpler search
      t.references :hgp_cmis_folder
      t.string :name, :null => false      
      t.boolean :dirty
      t.boolean :notification, :default => false, :null => false
      
      t.boolean :deleted, :default => false, :null => false
      t.integer :deleted_by_user_id
      
      t.timestamps
    end
    
    create_table :hgp_cmis_file_revisions do |t|
      t.references :hgp_cmis_file, :null => false
      t.integer :source_hgp_cmis_file_revision_id
      
      t.string :name, :null => false
      t.references :hgp_cmis_folder
      
      t.string :disk_filename, :null => false
      t.integer :size
      t.string :mime_type
      t.text :path      
      
      t.string :title
      t.text :description
      t.integer :workflow
      t.integer :major_version, :null => false
      t.integer :minor_version, :null => false
      t.text :comment
      
      t.boolean :deleted, :default => false, :null => false
      t.integer :deleted_by_user_id
      
      t.references :user, :null => false
      t.timestamps
      
      t.integer :project_id, :null => false
    end
    
    create_table :hgp_cmis_file_locks do |t|
      t.references :hgp_cmis_file, :null => false
      t.boolean :locked, :default => false, :null => false
      t.references :user, :null => false
      t.timestamps
    end
    
    create_table :hgp_cmis_project_params do |t|
      t.column :project_id, :integer
      t.column :param, :string
      t.column :value, :string      
    end
    
    create_table :hgp_cmis_file_revision_accesses do |t|
      t.references :hgp_cmis_file_revision, :null => false
      t.integer :action, :default => 0, :null => false  # 0 ... download, 1 ... email
      t.references :user, :null => false
      t.timestamps
    end
    
    add_column :projects, :hgp_cmis_description, :text
    add_column :members, :hgp_cmis_mail_notification, :boolean
    
  end

  def self.down
    drop_table :hgp_cmis_file_revisions
    drop_table :hgp_cmis_files
    drop_table :hgp_cmis_folders
    drop_table :hgp_cmis_file_locks
    drop_table :hgp_cmis_project_params
    drop_table :hgp_cmis_file_revision_accesses
    
    remove_column :projects, :hgp_cmis_description
    remove_column :members, :hgp_cmis_mail_notification
  end
end
