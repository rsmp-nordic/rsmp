# RSMP site
#
# Handles connection to a supervisor.
# We connect to the supervisor.

require_relative 'node'
require_relative 'remote_supervisor'

module RSMP
  class Site < Node
    attr_reader :rsmp_versions, :site_id, :site_settings, :logger

    def initialize options
      handle_site_settings options
      @logger = options[:logger] || RSMP::Logger.new(self, @site_settings["log"])
      @remote_supervisors = []
    end

    def handle_site_settings options
      if options[:site_settings]
        @site_settings = options[:site_settings]
      else
        if options[:site_settings_path]
          @site_settings = YAML.load_file(options[:site_settings_path])
        else
          raise "site_settings or site_settings_path must be present"
        end
      end

      required = ["supervisor_ip","port","rsmp_versions","site_id","watchdog_interval","watchdog_timeout",
                  "acknowledgement_timeout","command_response_timeout","log"]
      check_required_settings @site_settings, required

      # randomize site id
      #@site_settings["site_id"] = "RN+RC#{rand(9999).to_i}"
    end

    def start
      super
      # TODO for each supervisor we want to connect to
      @socket_thread = Thread.new do
        loop do
          begin
            connect
            wait_until_reconnect
          rescue SystemCallError => e # all ERRNO errors
            log str: "Exception: #{e.to_s}", level: :error
          rescue StandardError => e
            log str: ["Exception: #{e}",e.backtrace].flatten.join("\n"), level: :error
          end
        end
      end
    end

    def connect
      remote_supervisor = RemoteSupervisor.new site: self, settings: @site_settings, logger: @logger
      @remote_supervisors.push remote_supervisor
      remote_supervisor.run
      @remote_supervisors.delete remote_supervisor
    end

    def wait_until_reconnect
      interval = @site_settings["reconnect_interval"]
      log str: "Waiting #{interval} seconds before trying to reconnect", level: :info
      sleep interval
    end

    def stop
      log str: "Stopping site #{@site_id}", level: :info
      super
      @remote_supervisors.each { |site| site.terminate }
      @remote_supervisors.clear
    end

    def starting
      log str: "Starting site #{@site_settings["site_id"]} on port #{@site_settings["port"]}", level: :info
    end

  end
end