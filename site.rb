# RSMP site
#
# Handles connector to a supervisor.
# We connect to the supervisor.

require_relative 'node'
require_relative 'site_connector'

module RSMP
  class Site < Node
    attr_reader :rsmp_versions, :site_id, :site_settings, :logger, :remote_supervisors

    def initialize options
      super options
      handle_site_settings options
      @logger = options[:logger] || RSMP::Logger.new(self, @site_settings["log"])
      
      @remote_supervisors_mutex = Mutex.new
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

      required = ["supervisors","rsmp_versions","site_id","watchdog_interval","watchdog_timeout",
                  "acknowledgement_timeout","command_response_timeout","log"]
      check_required_settings @site_settings, required

      # randomize site id
      #@site_settings["site_id"] = "RN+SI#{rand(9999).to_i}"

    end

    def start
      super
      @site_settings["supervisors"].each do |supervisor_settings|
        @connection_threads << Thread.new do
          remote_supervisor = SiteConnector.new({
            site: self, 
            settings: @site_settings, 
            ip: supervisor_settings["ip"],
            port: supervisor_settings["port"],
            logger: @logger
          })
          @remote_supervisors_mutex.synchronize do
            @remote_supervisors << remote_supervisor
          end

          loop do
            begin
              remote_supervisor.run
              remote_supervisor.reconnect_delay
            rescue SystemCallError => e # all ERRNO errors
              log str: "Exception: #{e.to_s}", level: :error
            rescue StandardError => e
              log str: ["Exception: #{e}",e.backtrace].flatten.join("\n"), level: :error
            end
          end
        end
      end
    end

    def stop
      log str: "Stopping site #{@site_settings["site_id"]}", level: :info
      @remote_supervisors.each do |remote_supervisor|
        remote_supervisor.stop
      end
      @remote_supervisors.clear
      super
    end
 
    def starting
      log str: "Starting site #{@site_settings["site_id"]} on port #{@site_settings["port"]}", level: :info
    end
  end
end