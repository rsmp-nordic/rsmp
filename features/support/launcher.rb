# Utilities to start/stop the ruby rsmp server
#
# Keeping it running in the background instead of starting/stopping it for each scenario
# provides a big speed-up.

class Launcher
  attr_reader :supervisor_settings, :sites_settings, :supervisor, :remote_site, :archive

  def initialize
    load_settings

    if ENV["SITE"]=="internal" || 
        (ENV["SITE"]!="external" && @supervisor_settings["cucumber"] && @supervisor_settings["cucumber"]["site"].to_s == "internal")
      start_site
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

  def restart options={}
    stop
    start options
  end

  def start options={}
    return if @supervisor
    load_settings options

    @archive = RSMP::Archive.new

    @supervisor = RSMP::Supervisor.new(
      supervisor_settings: @supervisor_settings,
      sites_settings: @sites_settings,
      archive: @archive
    )
    @supervisor.start

    main_site_settings = @sites_settings.first

    # when we're running an internal site, we don't have to rely on the reconnect interval.
    # instead we ask the site to connect immediately:
    @site.reconnect if @site

    # wait for site to connect
    @remote_site = @supervisor.wait_for_site :any, @supervisor_settings["site_connect_timeout"]
    raise RSMP::TimeoutError unless @remote_site

    # and wait for site to be ready
    ready = @remote_site.wait_for_state :ready, @supervisor.supervisor_settings["site_ready_timeout"]
    raise RSMP::TimeoutError unless ready
  end

  def stop
    if @supervisor
      @supervisor.stop
      @supervisor = nil
    end
  end
end
