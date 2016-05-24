# encoding: UTF-8
# Encoding: UTF-8
# Written by: Signo-Net
# Email: clientes@signo-net.com 
# Web: http://www.signo-net.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

require 'pp'
require 'rubygems'     
require 'active_cmis' 

module HgpCmisModule

  class HgpCmisException < RuntimeError
    def initialize
      super
    end
  end

  attr_accessor :client
  
  def cmis_connect(params)
    begin
      @params = params
      @client = ActiveCMIS.connect(@params)
      return true
    rescue Errno::EHOSTUNREACH => e
      @client = nil
      raise HgpCmisException.new, l(:unable_connect_hgp_cmis)
      return false
    rescue Errno::ECONNREFUSED => e
      @client = nil
      raise HgpCmisException.new, l(:unable_connect_hgp_cmis)
      return false
    rescue ActiveCMIS::Error::ObjectNotFound => e
      @client = nil
      raise HgpCmisException.new, l(:repository_not_found)
      return false
    rescue ActiveCMIS::HTTPError => e
      @client = nil
      puts e.message
      raise HgpCmisException.new, l(:hgp_cmis_authentication_failed)
      return false
    end  
  end
  
  ###########################
  #   Documents Methods     #
  ###########################
  
  def save_document(path, documentName, contentStream)
    save_document_relative(path, documentName, contentStream, true)
  end
  
  def save_document_relative(path, documentName, contentStream, isRelativePath)    
    # Call save_folder, just in case it doesn't exist
    folder = save_folder_relative(path, isRelativePath)
    
    # Create HgpCmis document
    docType = @client.type_by_id("cmis:document")
    if (docType.content_stream_allowed == "notallowed")
      docType = @client.type_by_id("File")
    end
    newDocument = docType.new("cmis:name" => documentName)
    newDocument.file(folder)
    newDocument.set_content_stream(:data=>contentStream, :overwrite=>true)
    newDocument.save
    
    folder.reload
  end  
  
  def copy_document(fromPath, toPath)
    copy_document_relative(fromPath, toPath, true)
  end
  
  def copy_document_relative(fromPath, toPath, isRelativePath)
    # Read document content
    content = read_document_relative(fromPath, isRelativePath)
    
    # Save document into destination folder
    save_document_relative(get_path_to_folder(toPath), get_document_name(toPath), content, isRelativePath)    
  end
  
  def move_document(fromPath, toPath)
    move_document_relative(fromPath, toPath, true)
  end
  
  def move_document_relative(fromPath, toPath, isRelativePath)
    # Copy document content
    copy_document_relative(fromPath, toPath, isRelativePath)
    
    # Remove old document
    remove_document_relative(fromPath, isRelativePath)    
  end
  
  def read_document(path)
    return read_document_relative(path, true)
  end
  
  def read_document_relative(path, isRelativePath)
    document = get_document_relative(path, isRelativePath)
    #document = @client.object_by_id("workspace://SpacesStore/1b3c673e-1353-4764-873c-cd846665f8b0")
    if (document != nil)
      return document.content_stream.get_data[:data]
    else 
      return nil
    end
  end
  
  def get_document(path)
    return get_document_relative(path, true)
  end
  
  def get_document_relative(path, isRelativePath)
    parent = get_folder_relative(get_path_to_folder(path), isRelativePath)
    if (parent != nil)
      aux = parent.items.select {|o| o.is_a?(ActiveCMIS::Document) && o.cmis.name == get_document_name(path)}
      res = aux.first
    end
    return res
  end 
  
  def remove_document(path)
    remove_document_relative(path, true)
  end
  
  def remove_document_relative(path, isRelativePath)
    document = get_document_relative(path, isRelativePath)
    if (document != nil)
      document.destroy
      
      # Update parent folder 
      parentPath = get_path_to_folder(path)
      parentFolder = get_folder_relative(parentPath, isRelativePath)
      parentFolder.reload
    end    
  end
  
  ###########################
  #     Folders Methods     #
  ###########################
  
  def save_folder(path)
    return save_folder_relative(path, true)
  end
  
  def save_folder_relative(path, isRelativePath)
    res = nil
    
    if (path == nil or path.empty? or path == "/")
      # Path is root folder
      if (isRelativePath)
        # If the root is relative, keep going to path base
        res = save_folder_relative(@params['documents_path_base'], false);
      else 
        res = @client.object_by_path("/")
      end
      
    elsif (!exists_path_relative(path, isRelativePath))
      # Build path
      parentPath = get_path_to_folder(path);
      
      # Recursively create parent folders
      parent = save_folder_relative(parentPath, isRelativePath);      
      
      # Create the cmis folder
      folderName = get_folder_name(path);
      folderType = @client.type_by_id("cmis:folder")
      newFolder = folderType.new("cmis:name" => folderName)
      newFolder.file(parent)
      newFolder.save
      
      # Reload parent
      parent.reload
      
      res = newFolder    
    else 
      res = get_folder_relative(path, isRelativePath)    
    end
    
    # Reload folder content
    res.reload
    
    return res    
  end
  
  def copy_folder(fromPath, toPath)
    copy_folder_relative(fromPath, toPath, true)
  end
  
  def copy_folder_relative(fromPath, toPath, isRelativePath)
    # Create destination folder
    save_folder_relative(toPath, isRelativePath)
    
    # Get source folder
    sourceFolder = get_folder_relative(fromPath, isRelativePath)
    
    # Copy subfolders in folder
    sourceFolder.items.select {|o| o.is_a?(ActiveCMIS::Folder)}.map {|o|
      copy_folder_relative(compose_path(fromPath, o.name), compose_path(toPath, o.name), isRelativePath)
    }
    
    # Remove documents in folder
    sourceFolder.items.select {|o| o.is_a?(ActiveCMIS::Document)}.map {|o|
      copy_document_relative(compose_path(fromPath, o.name), compose_path(toPath, o.name), isRelativePath)
    }
  end
  
  def move_folder(fromPath, toPath)
    move_folder_relative(fromPath, toPath, true)
  end
  
  def move_folder_relative(fromPath, toPath, isRelativePath)
    # Copy document content
    copy_folder_relative(fromPath, toPath, isRelativePath)
    
    # Remove old document
    remove_folder_relative(fromPath, isRelativePath)    
  end
  
  def get_folder(path)
    get_folder_relative(path, true)
  end
  
  def get_folder_relative(path, isRelativePath)
    res = nil
    begin       
      # Path is root folder
      if (isRelativePath)
        # If the root is relative, keep going to path base
        completePath = compose_path(@params['documents_path_base'], path);
      else
        completePath = path
      end
      
      if (!completePath.start_with?"/")
        completePath = "/" + completePath
      end
      res = @client.object_by_path(completePath)
      
      if (res != nil)
        # Reload folder content
        res.reload
      end
    rescue ActiveCMIS::Error::ObjectNotFound
      puts "No se ha encontrado la carpeta " + completePath
    rescue ActiveCMIS::HTTPError::ServerError => e
      flash[:error] = l(:hgp_cmis_user_permission_denied)
      #redirect_to :controller => "hgp_cmis", :action => "login"
    end
    
    return res
    
  end
  
  def get_folder_by_key(key)
  	return @client.object_by_id(key)
  end
  
  def remove_folder(path)
    remove_folder_relative(path, true)
  end
  
  def remove_folder_relative(path, isRelativePath)    
    folder = get_folder_relative(path, isRelativePath)
    
    if (folder != nil)
      # Remove subfolders in folder
      folder.items.select {|o| o.is_a?(ActiveCMIS::Folder)}.map {|o|        
        remove_folder_relative(compose_path(path, o.name), isRelativePath)
      }  
      
      # Remove documents in folder
      folder.items.select {|o| o.is_a?(ActiveCMIS::Document)}.map {|o|
        remove_document_relative(compose_path(path, o.name), isRelativePath)
      }
      
      folder.destroy
      
      # Update parent folder 
      parentPath = get_path_to_folder(path)
      parentFolder = get_folder_relative(parentPath, isRelativePath)
      parentFolder.reload
    end    
  end
  
  def exists_path_relative(path, isRelativePath)
    if (get_folder_relative(path, isRelativePath) == nil)
      return false
    else
      return true
    end
  end
  
  def exists_path(path)
    return exists_path_relative(path, true)
  end
  
  def get_documents_in_folder(path)
    return get_documents_in_folder_relative(path, true)
  end
  
  def get_documents_in_folder_relative(path, isRelativePath)
    folder = get_folder_relative(path, isRelativePath)
    if (folder != nil)
      return folder.items.select {|o| o.is_a?(ActiveCMIS::Document)}
    else
      return []
    end
  end
  
  def get_folders_in_folder(path)
    return get_folders_in_folder_relative(path, true)
  end
  
  def get_folders_in_folder_relative(path, isRelativePath)
    folder = get_folder_relative(path, isRelativePath)
    res = []
    
    if (folder != nil)  
      #carpetas = @client.query("SELECT cmis:objectId FROM cmis:folder WHERE cmis:parentId='" + folder.key + "'")
      #carpetas.each {|carpeta|
      #  pp carpeta
      #  pp carpeta.property_by_id("cmis:objectId")
      #  subcarpeta = @client.object_by_id(carpeta.property_by_id("cmis:objectId"))
      #  res.push(subcarpeta)
      #  pp subcarpeta
      #  puts subcarpeta.attribute("cmis:name")
      #  puts "******"        
      #}      
      
      return folder.items.select {|o| o.is_a?(ActiveCMIS::Folder)}
    end
    
    return res
  end
  
  ###########################
  #         Utils           #
  ###########################
  
  def get_path_to_folder(documentUri)
    if documentUri != nil and !documentUri.empty?
      
      if (documentUri.end_with?"/")
        documentUri = substring_before_last(documentUri, "/")
      end
      
      if (documentUri.include?"/")
        return substring_before_last(documentUri, "/")
      else
        return "/"
      end
      
    else
      return ""
    end  
  end
  
  def get_document_name(documentUri)
    if (documentUri != nil and !documentUri.empty?)
      if (!documentUri.include?"/")
        return documentUri
      else
        return substring_after_last(documentUri, "/")
      end
    else
      return ""
    end
  end
  
  def get_folder_name(folderUri)    
    if (folderUri != nil and !folderUri.empty?)      
      if (folderUri.end_with?"/")
        folderUri = substring_before_last(folderUri, "/")
      end
      if (!folderUri.include?"/")
        return folderUri;
      else
        return substring_after_last(folderUri, "/")
      end
    else
      return ""
    end
  end
  
  def substring_before_last(cadena, separador) 
    lastIndex = cadena.rindex(separador)
    return cadena[0, lastIndex]
  end
  
  def substring_after_last(cadena, separador) 
    lastIndex = cadena.rindex(separador)
    if (lastIndex != nil)
      return cadena[lastIndex + 1, cadena.length - 1]
    else
      return ""
    end
  end
  
  def get_stream_content(absolutePath)
    return File.open(absolutePath, "rb") {|io| io.read}
  end
  
  def compose_path(path, documentName)
    if (path.end_with?"/")
      if (documentName.start_with?"/")
        return path + documentName[1, documentName.size - 1]
      else
        return path + documentName
      end
    else
      if (documentName.start_with?"/")
        return path + documentName
      else
        return path + "/" + documentName
      end      
    end
  end
  
  def map_repository_folder_to_redmine_folder(folder, folder_path = "")
    redmineFolder = HgpCmisFolder.new
    redmineFolder.project_id = @project.id
    if (!@folder.nil?)
      redmineFolder.hgp_cmis_folder_id = @folder.id
    end
    puts folder.class.to_s
    redmineFolder.title = folder.cmis.name
    redmineFolder.description = ''
    redmineFolder.path =  folder_path
    if (!redmineFolder.path.end_with?"/") 
      redmineFolder.path += "/"
    end
    redmineFolder.path += folder.cmis.name
    #redmineFolder.path = remove_root_path(folder.cmis.path)
    redmineFolder.created_at = folder.cmis.creationDate
    redmineFolder.updated_at = folder.cmis.lastModificationDate
    redmineFolder.user = User.current
    
    #guardo tambien el uuid de alfresco
    redmineFolder.alfresco_uuid = folder.key
    
    return redmineFolder
  end
  
  def map_repository_doc_to_redmine_file(document, folder_path = "")
    file = HgpCmisFile.new
    
    file.project_id = @project.id
    if (!@folder.nil?)
      file.hgp_cmis_folder_id = @folder.id
    end
    file.name = document.cmis.name
    file.created_at = document.cmis.creationDate
    file.updated_at = document.cmis.lastModificationDate
    file.revisions = [map_repository_doc_to_redmine_revision(document, nil, folder_path)]
    
    return file
  end
  
  def map_repository_doc_to_redmine_revision(document, file, folder_path = "")
    revision = HgpCmisFileRevision.new
    if (file != nil)
      revision.hgp_cmis_file_id = file.id
    end
    revision.name = document.cmis.name
    if (!@folder.nil?)
      revision.hgp_cmis_folder_id = @folder.id
    end
    revision.disk_filename = document.cmis.name
    revision.size = document.cmis.contentStreamLength
    revision.mime_type = document.cmis.contentStreamMimeType 
    revision.path = folder_path + "/" + document.cmis.name
    revision.title = document.cmis.name
    revision.description = ''
    revision.major_version = 1
    revision.minor_version = 0
    revision.created_at = document.cmis.creationDate
    revision.updated_at = document.cmis.lastModificationDate
    revision.user_id = User.current
    revision.project_id = @project.id
    # Marco por defecto como aprobado
    revision.workflow = 2
    revision.file = file
    
    return revision
  end
  
  def current_folder_path
    if @folder.nil?
      path = ""
    else
      path = @folder.path
    end
    return path
  end
  
  def remove_root_path(path)
    root_path = @params['documents_path_base']
    if (!root_path.start_with?("/"))
      root_path = "/" + root_path
    end
    
    return path.sub(root_path, "")
  end
  
end

