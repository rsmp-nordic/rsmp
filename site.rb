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
      handle_site_settings options
      super options.merge log_settings: @site_settings["log"]
      @remote_supervisors = []
      @sleep_condition = Async::Condition.new
    end

    def handle_site_settings options
      unless options[:site_settings_path] || options[:site_settings]
        raise ArgumentError.new("site_settings or site_settings_path must be present")
      end

      if options[:site_settings_path]
        @site_settings = YAML.load_file(options[:site_settings_path])
      end

      if options[:site_settings]
        options = options[:site_settings].map { |k,v| [k.to_s,v] }.to_h   #convert symbol keys to string keys
        @site_settings.merge! options
      end

      required = [:supervisors,:rsmp_versions,:site_id,:watchdog_interval,:watchdog_timeout,
                  :acknowledgement_timeout,:command_response_timeout,:log]
      check_required_settings @site_settings, required

      # randomize site id
      #@site_settings["site_id"] = "RN+SI#{rand(9999).to_i}"

    end

    def reconnect
      @sleep_condition.signal
    end

    def start_action
      @site_settings["supervisors"].each do |supervisor_settings|
        @task.async do |task|
          task.annotate "site_connector"
          connect_to_supervisor task, supervisor_settings
        end
      end
    end

    def connect_to_supervisor task, supervisor_settings
      remote_supervisor = SiteConnector.new({
        site: self,
        task: @task,
        settings: @site_settings, 
        ip: supervisor_settings['ip'],
        port: supervisor_settings['port'],
        logger: @logger,
        archive: @archive
      })
      @remote_supervisors << remote_supervisor
      run_site_connector task, remote_supervisor
    ensure
      @remote_supervisors.delete remote_supervisor
    end

    def run_site_connector task, remote_supervisor
      loop do
        remote_supervisor.run       # run until disconnected
      rescue IOError => e
        log str: "Stream error: #{e}", level: :warning
      rescue SystemCallError => e # all ERRNO errors
        log str: "Reader exception: #{e.to_s}", level: :error
      rescue StandardError => e
        log str: ["Reader exception: #{e}",e.backtrace].flatten.join("\n"), level: :error
      ensure
        begin
          # sleep until waken by reconnect() or the reconnect interval passed
          task.with_timeout(@site_settings["reconnect_interval"]) { @sleep_condition.wait }
        rescue Async::TimeoutError
          # ignore
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
      log str: "Starting site #{@site_settings["site_id"]} on port #{@site_settings["port"]}",
          level: :info,
          timestamp: RSMP.now_object
    end
  end
end