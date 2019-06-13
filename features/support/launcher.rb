# Utilities to start/stop the ruby rsmp server
#
# Keeping it running in the background instead of starting/stopping it for each scenario
# provides a big speed-up.

class Launcher
  attr_reader :supervisor_settings, :sites_settings, :server, :client

  def initialize
    load_settings
  end

  def relative_filename filename
    dir = File.dirname(__FILE__)
    File.expand_path File.join(dir,filename)
  end

  def load_settings options={}
    @supervisor_settings = YAML.load_file(relative_filename('supervisor.yaml'))
    @supervisor_settings.merge! options[:supervisor_settings] if options[:supervisor_settings]


    @sites_settings = YAML.load_file(relative_filename('sites.yaml'))
  end

  def restart options={}
    stop
    start options
  end

  def start options={}
    return if @server
    load_settings options

    @server = RSMP::Server.new(
      supervisor_settings: @supervisor_settings,
      sites_settings: @sites_settings
    )
    @server.start

    main_site_settings = @sites_settings.first

    @client = @server.wait_for_site main_site_settings["site_id"], @supervisor_settings["site_connect_timeout"]
    raise RSMP::TimeoutError unless @client

    ready = @client.wait_for_state :ready, @server.supervisor_settings["site_ready_timeout"]
    raise RSMP::TimeoutError unless ready
  end

  def stop
    if @server
      @server.stop
      @server = nil
    end
  end
end
