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

class HgpCmisStateController < ApplicationController
  unloadable
  
  menu_item :hgp_cmis
  
  before_filter :find_project

  def user_pref_save
    HgpCmisProjectSettings::config_params.each do |param|
      HgpCmisProjectSettings::set_project_param_value(@project, param, params[param])
    end
      
    redirect_to :controller => 'projects', :action => 'settings', :id => @project, :tab => 'hgp_cmis'
  end
  
  private
  
  def find_project
    @project = Project.find(params[:id])
  end
  
  def check_project(entry)
    if !entry.nil? && entry.project != @project
      raise HgpCmisAccessError, l(:error_entry_project_does_not_match_current_project) 
    end
  end
  
end
