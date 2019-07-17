require_relative '../../supervisor'
require_relative '../../site'

module RSMP
  class Launcher

    def start_supervisor
    	return if @supervisor
      load_supervisor_settings
    	@supervisor = RSMP::Supervisor.new(
        supervisor_settings: @supervisor_settings,
        sites_settings: @sites_settings
      )
      @supervisor.start
      @supervisor
    end

    def stop_supervisor
      if @supervisor
        @supervisor.stop
        @supervisor = nil
      end
    end

    def start_site
      return if @site
      load_site_settings
      @site = RSMP::Site.new(
        site_settings: @site_settings
      )
      @site.start
    end

    def stop_site
      if @site
        @site.stop
        @site = nil
      end
    end

    private

    def relative_filename filename
      dir = File.dirname(__FILE__)
      File.expand_path File.join(dir,filename)
    end

    def load_supervisor_settings options={}
      @supervisor_settings = YAML.load_file(relative_filename('supervisor.yaml'))
      @supervisor_settings.merge! options[:supervisor_settings] if options[:supervisor_settings]
      @sites_settings = YAML.load_file(relative_filename('sites.yaml'))
      if ENV["LOG"] == "yes" then
        @supervisor_settings["log"]["active"] = true
      end
    end

    def load_site_settings options={}
      @site_settings = YAML.load_file(relative_filename('site.yaml'))
      if ENV["LOG"] == "yes" then
        @site_settings["log"]["active"] = true
      end
    end
    
  end
end