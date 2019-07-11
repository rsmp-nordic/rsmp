require_relative '../../supervisor'
require_relative '../../site'
require_relative '../../supervisor'
require_relative '../../site'

module Launcher
  def relative_filename filename
    dir = File.dirname(__FILE__)
    File.expand_path File.join(dir,filename)
  end

  def load_settings options={}
    @supervisor_settings = YAML.load_file(relative_filename('supervisor.yaml'))
    @supervisor_settings.merge! options[:supervisor_settings] if options[:supervisor_settings]
    @sites_settings = YAML.load_file(relative_filename('sites.yaml'))

    @site_settings = YAML.load_file(relative_filename('site.yaml'))

    if ENV["LOG"] == "yes" then
      @supervisor_settings["log"]["active"] = true
      @site_settings["log"]["active"] = true
    end
  end

  def start_supervisor
  	return if @supervisor

    load_settings
  	@archive = RSMP::Archive.new

  	@supervisor = RSMP::Supervisor.new({
      supervisor_settings: @supervisor_settings,
      sites_settings: @sites_settings,
      archive: @archive
    })
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
    @site_archive = RSMP::Archive.new
    @site = RSMP::Site.new(
      site_settings: @site_settings,
      archive: @site_archive
    )
    @site.start
  end
end
