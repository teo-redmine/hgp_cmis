# encoding: UTF-8
require File.dirname(__FILE__) + '/../test_helper'

class HgpCmisFolderTest < ActiveSupport::TestCase
  fixtures :projects, :users, :hgp_cmis_folders, :hgp_cmis_files, :hgp_cmis_file_revisions,
           :roles, :members, :member_roles, :enabled_modules, :enumerations

  def test_folder_creating
    assert_not_nil(hgp_cmis_folders(:one))
  end
  
end
