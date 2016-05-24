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

#begin
#  require 'xapian'
#  $xapian_bindings_available = true
#rescue LoadError
#  Rails.logger.info "REDMAIN_XAPIAN ERROR: No Ruby bindings for Xapian installed !!. PLEASE install Xapian search engine interface for Ruby."
#  $xapian_bindings_available = false
#end

class HgpCmisFile < ActiveRecord::Base  
  unloadable
  belongs_to :project
  belongs_to :folder, :class_name => "HgpCmisFolder", :foreign_key => "hgp_cmis_folder_id"
  has_many :revisions, -> { where ("hgp_cmis_file_revisions.deleted = false"), order("major_version DESC, minor_version DESC, updated_at DESC")}, :class_name => "HgpCmisFileRevision", :foreign_key => "hgp_cmis_file_id"
  has_many :locks, -> { order "updated_at DESC" }, :class_name => "HgpCmisFileLock", :foreign_key => "hgp_cmis_file_id" 
  belongs_to :deleted_by_user, :class_name => "User", :foreign_key => "deleted_by_user_id"
  
  validates_presence_of :name
  validates_format_of :name, :with => HgpCmisFolder.invalid_characters,
    :message => l(:error_contains_invalid_character)
  
  validate :validates_name_uniqueness 
  
  def validates_name_uniqueness 
    existing_file = HgpCmisFile.find_file_by_name(self.project, self.folder, self.name)
    errors.add(:name, l("activerecord.errors.messages.taken")) unless
      existing_file.nil? || existing_file.id == self.id
  end
  
  acts_as_event :title => Proc.new {|o| "#{o.title} - #{o.name}"},
                :description => Proc.new {|o| o.description },
                :url => Proc.new {|o| {:controller => "hgp_cmis_files", :action => "show", :id => o, :download => ""}},
                :datetime => Proc.new {|o| o.updated_at },
                :author => Proc.new {|o| o.last_revision.user }
  
  #TODO: place into better place
  def self.storage_path
    storage_dir = Setting.plugin_hgp_cmis["hgp_cmis_storage_directory"].strip
    if !File.exists?(storage_dir)
      Dir.mkdir(storage_dir)
    end
    storage_dir
  end
  
  def self.project_root_files(project)
    where(hgp_cmis_folder_id: nil, project_id: project.id, deleted: false).order(name: :ASC)
  end
  
  def self.find_file_by_name(project, folder, name)
    if folder.nil?
      find_by project_id: project.id, deleted: false, name: name, hgp_cmis_folder_id: nil
    else
      find_by hgp_cmis_folder_id: folder.id, project_id: project.id, name: name, deleted: false
    end
  end

  def last_revision
    self.revisions.first
  end

  def delete
    if locked_for_user?
      errors.add_to_base(l(:error_file_is_locked))
      return false 
    end
    # Borro SIEMPRE IRREVERSIBLEMENTE
      self.revisions.each {|r| r.delete(true)}
      self.locks.each {|l| l.destroy}
      self.destroy
  end
  
  def locked?
    self.locks.empty? ? false : self.locks[0].locked
  end
  
  def locked_for_user?
    self.locked? && self.locks[0].user != User.current
  end
  
  def lock
    l = HgpCmisFileLock.file_lock_state(self, true)
    self.reload
    return l
  end
  
  def unlock
    l = HgpCmisFileLock.file_lock_state(self, false)
    self.reload
    return l
  end
  
  def title
    self.last_revision.title
  end
  
  def description
    self.last_revision.description
  end
  
  def version
    self.last_revision.version
  end
  
  def workflow
    self.last_revision.workflow
  end
  
  def size
    self.last_revision.size
  end
  
  def hgp_cmis_path
    path = self.folder.nil? ? [] : self.folder.hgp_cmis_path
    path.push(self)
    path
  end
  
  def hgp_cmis_path_str
    path = self.hgp_cmis_path
    string_path = path.map { |element| element.title }
    string_path.join("/")
  end
  
  def notify?
    return true if self.notification
    return true if folder && folder.notify?
    return false
  end
  
  def notify_deactivate
    self.notification = false
    self.save!
  end
  
  def notify_activate
    self.notification = true
    self.save!
  end
  
  def display_name
    #if self.name.length > 33
    #  extension = File.extname(self.name)
    #  return self.name[0, self.name.length - extension.length][0, 25] + "..." + extension
    #else 
      return self.name
    #end
  end
  
  # Returns an array of projects that current user can copy file to
  def self.allowed_target_projects_on_copy
    projects = []
    if User.current.admin?
      projects = Project.visible.all
    elsif User.current.logged?
      User.current.memberships.each {|m| projects << m.project if m.roles.detect {|r| r.allowed_to?(:hgp_cmis_file_manipulation)}}
    end
    projects
  end
  
  def move_to(project, folder)
    if self.locked_for_user?
      errors.add_to_base(l(:error_file_is_locked))
      return false 
    end
    
    new_revision = self.last_revision.clone
    
    new_revision.folder = folder ? folder : nil
    new_revision.project = folder ? folder.project : project
    new_revision.comment = l(:comment_moved_from, :source => "#{self.project.identifier}:#{self.hgp_cmis_path_str}") 

    self.folder = new_revision.folder
    self.project = new_revision.project

    return self.save && new_revision.save
  end
  
  def copy_to(project, folder)
    file = HgpCmisFile.new
    file.folder = folder ? folder : nil
    file.project = folder ? folder.project : project
    file.name = self.name
    file.notification = !Setting.plugin_hgp_cmis["hgp_cmis_default_notifications"].blank?

    new_revision = self.last_revision.clone
    
    new_revision.file = file
    new_revision.folder = folder ? folder : nil
    new_revision.project = folder ? folder.project : project
    new_revision.comment = l(:comment_copied_from, :source => "#{self.project.identifier}:#{self.hgp_cmis_path_str}")
    
    new_revision.save if file.save  
    
    return file
  end
  
  # To fullfill searchable module expectations
  def self.search(tokens, projects=nil, options={})
    tokens = [] << tokens unless tokens.is_a?(Array)
    projects = [] << projects unless projects.nil? || projects.is_a?(Array)

    find_options = {:include => [:project,:revisions]}
    find_options[:order] = "hgp_cmis_files.updated_at " + (options[:before] ? 'DESC' : 'ASC')
    
    limit_options = {}
    limit_options[:limit] = options[:limit] if options[:limit]
    if options[:offset]
      limit_options[:conditions] = "(hgp_cmis_files.updated_at " + (options[:before] ? '<' : '>') + "'#{connection.quoted_date(options[:offset])}')"
    end
    
    columns = ["hgp_cmis_files.name","hgp_cmis_file_revisions.title", "hgp_cmis_file_revisions.description"]
    columns = ["hgp_cmis_file_revisions.title"] if options[:titles_only]
            
    token_clauses = columns.collect {|column| "(LOWER(#{column}) LIKE ?)"}
    
    sql = (['(' + token_clauses.join(' OR ') + ')'] * tokens.size).join(options[:all_words] ? ' AND ' : ' OR ')
    find_options[:conditions] = [sql, * (tokens.collect {|w| "%#{w.downcase}%"} * token_clauses.size).sort]
    
    project_conditions = []
    project_conditions << (Project.allowed_to_condition(User.current, :view_hgp_cmis_files))
    project_conditions << "#{HgpCmisFile.table_name}.project_id IN (#{projects.collect(&:id).join(',')})" unless projects.nil?
    
    results = []
    results_count = 0
    
    with_scope(:find => {:conditions => [project_conditions.join(' AND ') + " AND #{HgpCmisFile.table_name}.deleted = :false", {:false => false}]}) do
      with_scope(:find => find_options) do
        results_count = count(:all)
        results = find(:all, limit_options)
      end
    end
    
    if !options[:titles_only] && $xapian_bindings_available
      database = nil
      begin
        database = Xapian::Database.new(Setting.plugin_hgp_cmis["hgp_cmis_index_database"].strip)
      rescue
        Rails.logger.warn "REDMAIN_XAPIAN ERROR: Xapian database is not properly set or initiated or is corrupted."
      end

      unless database.nil?
        enquire = Xapian::Enquire.new(database)
        
        queryString = tokens.join(' ')
        qp = Xapian::QueryParser.new()
        stemmer = Xapian::Stem.new(Setting.plugin_hgp_cmis['hgp_cmis_stemming_lang'].strip)
        qp.stemmer = stemmer
        qp.database = database
        
        case Setting.plugin_hgp_cmis['hgp_cmis_stemming_strategy'].strip
          when "STEM_NONE" then qp.stemming_strategy = Xapian::QueryParser::STEM_NONE
          when "STEM_SOME" then qp.stemming_strategy = Xapian::QueryParser::STEM_SOME
          when "STEM_ALL" then qp.stemming_strategy = Xapian::QueryParser::STEM_ALL
        end
      
        if options[:all_words]
          qp.default_op = Xapian::Query::OP_AND
        else  
          qp.default_op = Xapian::Query::OP_OR
        end
        
        query = qp.parse_query(queryString)
  
        enquire.query = query
        matchset = enquire.mset(0, 1000)
    
        unless matchset.nil?
          matchset.matches.each {|m|
            docdata = m.document.data{url}
            dochash = Hash[*docdata.scan(/(url|sample|modtime|type|size)=\/?([^\n\]]+)/).flatten]
            filename = dochash["url"]
            if !filename.nil?
              hgp_cmis_attrs = filename.split("_")
              next if hgp_cmis_attrs[1].blank?
              next unless results.select{|f| f.id.to_s == hgp_cmis_attrs[1]}.empty?
              
              find_conditions =  HgpCmisFile.merge_conditions(limit_options[:conditions], :id => hgp_cmis_attrs[1], :deleted => false )
              hgp_cmis_file = HgpCmisFile.find(:first, :conditions => find_conditions )
    
              if !hgp_cmis_file.nil?
                if options[:offset]
                  if options[:before]
                    next if hgp_cmis_file.updated_at < options[:offset]
                  else
                    next if hgp_cmis_file.updated_at > options[:offset]
                  end
                end
              
                allowed = User.current.allowed_to?(:view_hgp_cmis_files, hgp_cmis_file.project)
                project_included = false
                project_included = true if projects.nil?
                if !project_included
                  projects.each {|x| 
                    project_included = true if x[:id] == hgp_cmis_file.project.id
                  }
                end
  
                if (allowed && project_included)
                  results.push(hgp_cmis_file)
                  results_count += 1
                end
              end
            end
          }
        end
      end    
    end
    
    [results, results_count]
  end
  
end