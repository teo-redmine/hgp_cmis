# encoding: UTF-8
class HgpCmisHooks < Redmine::Hook::ViewListener
  include HgpCmisModule
  
  # Para añadir un nuevo tab a la configuración del proyecto
  def add_projects_settings_tabs(context = {})
    if User.current.allowed_to?(:hgp_cmis_user_preferences, context[:project])
      context[:tabs].push({ :name => 'Cmis',
                                 :action  => :new_tab_action,
                                 :partial => 'projects/settings/hgp_cmis_tab',
                                 :label   => :hgp_cmis })
    end
  end
  
  # Para eliminar los registros que dependan del proyecto eliminado
  def add_project_delete(context = {})
    
    begin
      
      project = Project.find(context[:id])
      
      HgpCmisFileRevision.where(project_id: project.id).find_each do |row|
        row.delete
      end
      
      HgpCmisFile.where(project_id: project.id).find_each do |row|
        row.delete
      end
      
      HgpCmisFolder.where(project_id: project.id).each do |row|
        row.delete
      end

      HgpCmisProjectParam.find(project_id: project.id).each do |row|
        row.delete
      end

    rescue HgpCmisException=>e
      puts("No se han podido eliminar los registros del plugin CMIS. " + e.message)
    rescue ActiveCMIS::Error::PermissionDenied=>e
      puts("No se han podido eliminar los registros del plugin CMIS.")
    rescue Exception=>e
      puts("No se han podido eliminar los registros del plugin CMIS. " + e.message)
    end
    
  end
  
end
