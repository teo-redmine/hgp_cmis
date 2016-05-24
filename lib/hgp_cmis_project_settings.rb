# encoding: UTF-8

module HgpCmisProjectSettings

  class << self
    
    def server_login
      @sever_login
    end
    
    def server_login=(server_login)
      @server_login = server_login
    end
    
    def server_password=(server_password)
      @server_password = server_password
    end
    
    # Define los parámetros de configuración
    def config_params 
         
      # TODO Poner este array en una variable
      types = ["server_url", "repository_id", "documents_path_base"]
      return types
    end
    
    def get_project_param_row(project, param)
      # Busco el registro en base de datos
      
      aux = HgpCmisProjectParam.where(project_id: project.id.to_s, param: param)
      if (aux.empty?) 
        # Si no lo encuentro, busco la configuración del proyecto padre, si lo hay
        encontrado = HgpCmisProjectParam.new
        encontrado.project_id = project.id
        encontrado.param = param
        if (project.parent_id != nil)
          aux = get_project_param_row(Project.find(project.parent_id), param)
          encontrado.value = aux.value
        else
          # Si no hay proyecto padre, me quedo con la configuración por defecto
          encontrado.value = Setting.plugin_hgp_cmis[param]         
        end
        encontrado.save   
      else
        encontrado = aux[0]
      end
      return encontrado
    end
    
    def get_project_param_value(project, param)
      return get_project_param_row(project, param).value
    end
    
    def set_project_param_value(project, param, value)
      res = get_project_param_row(project, param)
      res.value = value
      res.save
    end
    
    def get_project_params(project)
      params = {}
      config_params.each do |param|
        params[param] = get_project_param_value(project, param)
      end
      params['server_login'] = @server_login
      params['server_password'] = @server_password
      return params
    end
     
  end 
  
end
