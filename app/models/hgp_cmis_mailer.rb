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

require "mailer"

class HgpCmisMailer < Mailer
  
  def files_updated(user, files)
    project = files[0].project
    files = files.select { |file| file.notify? }
    
    redmine_headers "Project" => project.identifier
    recipients get_notify_user_emails(user, files)
    subject project.name + ": HgpCmis files updated"
    body :user => user, :files => files, :project => project
    # TODO: correct way should be  render_multipart("files_updated", body), but other plugin broke it
    render_multipart(File.expand_path(File.dirname(__FILE__) + "/../views/hgp_cmis_mailer/" + "files_updated"), body)
  end
  
  def files_deleted(user, files)
    project = files[0].project
    files = files.select { |file| file.notify? }
    
    redmine_headers "Project" => project.identifier
    recipients = get_notify_user_emails(user, files)
    subject = project.name + ": HgpCmis files deleted"
    #body :user => user, :files => files, :project => project
    if recipients.any?
	    mail(:to => recipients,:subject => subject)    	
    end

    # TODO: correct way should be  render_multipart("files_updated", body), but other plugin broke it
    #render_multipart(File.expand_path(File.dirname(__FILE__) + "/../views/hgp_cmis_mailer/" + "files_deleted"), body)
  end
  
  def send_documents(user, email_to, email_cc, email_subject, zipped_content, email_plain_body)
    recipients      email_to
    if !email_cc.strip.blank?
      cc              email_cc
    end
    subject         email_subject
    from            user.mail
    content_type    "multipart/mixed"

    part "text/plain" do |p|
      p.body = email_plain_body
    end
  
    zipped_content_data = open(zipped_content, "rb") {|io| io.read }

    attachment :content_type => "application/zip",
             :filename => "Documents.zip",
             :body => zipped_content_data
  end
  
  
  private
  
  def get_notify_user_emails(user, files)
    if files.empty?
      return []
    end
    
    project = files[0].project
    
    notify_members = project.members
    notify_members = notify_members.select do |notify_member|
      notify_user = notify_member.user
      if notify_user.pref[:no_self_notified] && notify_user == user
        false
      else
        if notify_member.hgp_cmis_mail_notification.nil?
          case notify_user.mail_notification
          when 'all'
            true
          when 'selected'
            notify_member.mail_notification?
          when 'only_my_events'
            notify_user.allowed_to?(:hgp_cmis_file_approval, project) ? true : false
          when 'only_owner'
            notify_user.allowed_to?(:hgp_cmis_file_approval, project) ? true : false
          else
            false
          end
        else  
          notify_member.hgp_cmis_mail_notification
        end
      end
    end      

    notify_members.collect {|m| m.user.mail }
  end
  
end
