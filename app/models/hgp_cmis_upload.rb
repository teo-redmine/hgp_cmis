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

class HgpCmisUpload
  attr_accessor :name
  
  attr_accessor :disk_filename
  attr_reader :size
  attr_accessor :mime_type
  attr_accessor :title
  attr_accessor :description
      
  attr_accessor :comment
  attr_accessor :major_version
  attr_accessor :minor_version
  attr_accessor :locked
  
  attr_accessor :workflow
  
  def disk_file
    "#{HgpCmisHelper.temp_dir}/#{self.disk_filename}"
  end
  
  def self.create_from_uploaded_file(project, folder, uploaded_file)
    uploaded = {
      "disk_filename" => HgpCmisHelper.temp_filename(uploaded_file.original_filename),
      "content_type" => uploaded_file.content_type.to_s,
      "original_filename" => uploaded_file.original_filename,
    }
    
    File.open("#{HgpCmisHelper.temp_dir}/#{uploaded["disk_filename"]}", "wb") do |f| 
      while (buffer = uploaded_file.read(8192))
        f.write(buffer)
      end
    end
    HgpCmisUpload.new(project, folder, uploaded)
  end
  
  def initialize(project, folder, uploaded)
    @name = uploaded["original_filename"]
    hgp_cmis_file = HgpCmisFile.find_file_by_name(project, folder, @name)
    
    @disk_filename = uploaded["disk_filename"]
    @mime_type = uploaded["content_type"]
    @size = File.size(disk_file)
    
    if hgp_cmis_file.nil? || hgp_cmis_file.last_revision.nil?
      @title = HgpCmisFileRevision.filename_to_title(@name)
      @description = nil
      @major_version = 0
      @minor_version = 0
      @workflow = nil
    else
      last_revision = hgp_cmis_file.last_revision 
      @title = last_revision.title
      @description = last_revision.description
      @major_version = last_revision.major_version
      @minor_version = last_revision.minor_version
      @workflow = last_revision.workflow
    end
    
    @locked = !hgp_cmis_file.nil? && hgp_cmis_file.locked_for_user?
  end
  
end