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

class HgpCmisFileLock < ActiveRecord::Base
  unloadable
  belongs_to :file, :class_name => "HgpCmisFile", :foreign_key => "hgp_cmis_file_id"
  belongs_to :user  
  
  def self.file_lock_state(file, locked)
    lock = HgpCmisFileLock.new
    lock.file = file
    lock.user = User.current
    lock.locked = locked
    lock.save!
  end
  
end