#
# RSMP site
#
# Handles a single connection to supervisor.
# We connect to the supervisor.
#

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
        # load settings
        dir = File.dirname(__FILE__)
        if options[:site_settings_path]
          @site_settings = YAML.load_file(options[:site_settings_path])
        else
          raise "site_settings or site_settings_path must be present"
        end
      end
      raise "Site settings is empty" unless @site_settings
      raise "Site settings:supervisor_ip is missing" unless @site_settings["supervisor_ip"]
      raise "Site settings:port is missing" unless @site_settings["port"]
      raise "Site settings:rsmp_version is missing" unless @site_settings["rsmp_versions"]

      raise "Site settings:siteId is missing" unless @site_settings["site_id"]
      #@site_settings["site_id"] = "RN+RC#{rand(9999).to_i}"
      
      raise "Site settings:watchdog_interval is missing" if @site_settings["watchdog_interval"] == nil
      raise "Site settings:watchdog_timeout is missing" if @site_settings["watchdog_timeout"] == nil
      raise "Site settings:acknowledgement_timeout is missing" if @site_settings["acknowledgement_timeout"] == nil
      raise "Site settings:command_response_timeout is missing" if @site_settings["command_response_timeout"] == nil
      raise "Site settings:log is missing" if @site_settings["log"] == nil
    end

    def start
      @run = true
      starting

      # TODO for each supervisor we want to connect to
      # TODO when disconnected, reconnect at interval

      @socket_thread = Thread.new do

        remote_supervisor = RemoteSupervisor.new site: self, settings: @site_settings, logger: @logger
        @remote_supervisors.push remote_supervisor

        while @run
          begin
            remote_supervisor.run
          rescue SystemCallError => e # all ERRNO errors
            log str: "Exception: #{e.to_s}", level: :error
            break
          rescue StandardError => e
            log str: ["Exception: #{e}",e.backtrace].flatten.join("\n"), level: :error
            break
          end
        end
      end

    end

    def stop
      log str: "Stopping site id #{@site_id}", level: :info
      @remote_supervisors.each { |site| site.terminate }
      @remote_supervisors.clear
      join
    ensure
      exiting
    end

    def starting
      log str: "Starting site id #{@site_settings["site_id"]} on port #{@site_settings["port"]}", level: :info
    end

  end
end