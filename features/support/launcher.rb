# Utilities to start/stop the ruby rsmp server
#
# Keeping it running in the background instead of starting/stopping it for each scenario
# provides a big speed-up.

class Launcher
  attr_reader :supervisor_settings, :site_settings, :server, :client

  def initialize
    load_settings
  end

  def relative_filename filename
    dir = File.dirname(__FILE__)
    File.expand_path File.join(dir,filename)
  end

  def load_settings
    load_supervisor_settings relative_filename('supervisor.yml')
    load_site_settings relative_filename('site.yml')
  end

  def load_supervisor_settings filename
    @supervisor_settings = YAML.load_file(filename)
  end

  def load_site_settings filename
    @site_settings = YAML.load_file(filename)
  end

  def restart_server
    stop_server
    start_server
  end

  def start_server
    return if @server
    load_settings
    
    @server = RSMP::Server.new(@supervisor_settings)
    @server.start

    @client = @server.wait_for_site @site_settings["site_id"], @supervisor_settings["site_connect_timeout"]
    raise RSMP::TimeoutError unless @client

    ready = @client.wait_for_state :ready, @supervisor_settings["site_ready_timeout"]
    raise RSMP::TimeoutError unless ready
  end

  def stop_server
    p 'stop'
    if @server
      @server.stop
      @server = nil
    end
  end
end
