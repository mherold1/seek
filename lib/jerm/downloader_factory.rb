# To change this template, choose Tools | Templates
# and open the template in the editor.

module Jerm
  #Defaults to returning a HttpDownloader, unless specifed otherwise in config/downloaders.yml
  #If a different type of downloader is required, then an entry should be put into downloaders.yml with the project name (lower case and with underscores) as the key,
  # and the classname as the value. e.g. to use a XDownloader for BaCell-SysMo, add ba_cell_sys_mo: XDownloader
  class DownloaderFactory

    #defaults to the HttpDownloader, unless otherwise defined in the downloaders.yml
    def self.create project_name,username,password
      configpath=File.join(File.dirname(__FILE__),"config/downloaders.yml")
      config=YAML::load_file(configpath)
      downloader_class=config[project_key(project_name)] if config
      downloader_class ? Jerm.const_get(downloader_class).new(username,password) : HttpDownloader.new
    end

    def self.project_key project_name
      clean_project_name=project_name.gsub("-","")
      return clean_project_name.underscore
    end

  end
end