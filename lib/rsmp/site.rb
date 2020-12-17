# RSMP site
# The site initializes the connection to the supervisor.
# Connections to supervisors are handles via supervisor proxies.

module RSMP
  class Site < Node
    include SiteBase

    attr_reader :rsmp_versions, :site_settings, :logger, :proxies

    def initialize options={}
      initialize_site
      handle_site_settings options
      super options
      @proxies = []
      @sleep_condition = Async::Notification.new
    end

    def site_id
      @site_settings['site_id']
    end

    def handle_site_settings options
      @site_settings = {
        'site_id' => 'RN+SI0001',
        'supervisors' => [
          { 'ip' => '127.0.0.1', 'port' => 12111 }
        ],
        'rsmp_versions' => ['3.1.1','3.1.2','3.1.3','3.1.4'],
        'sxl' => 'traffic_light_controller',
        'sxl_version' => '1.0.7',
        'timer_interval' => 0.1,
        'watchdog_interval' => 1,
        'watchdog_timeout' => 2,
        'acknowledgement_timeout' => 2,
        'command_response_timeout' => 1,
        'status_response_timeout' => 1,
        'status_update_timeout' => 1,
        'site_connect_timeout' => 2,
        'site_ready_timeout' => 1,
        'reconnect_interval' => 0.1,
        'send_after_connect' => true,
        'components' => {
          'C1' => {}
        }
      }
      if options[:site_settings]
        converted = options[:site_settings].map { |k,v| [k.to_s,v] }.to_h   #convert symbol keys to string keys
        converted.compact!
        @site_settings.merge! converted
      end

      required = [:supervisors,:rsmp_versions,:site_id,:watchdog_interval,:watchdog_timeout,
                  :acknowledgement_timeout,:command_response_timeout]
      check_required_settings @site_settings, required

      setup_components @site_settings['components']
    end

    def reconnect
      @sleep_condition.signal
    end

    def start_action
      @site_settings["supervisors"].each do |supervisor_settings|
        @task.async do |task|
          task.annotate "site_proxy"
          connect_to_supervisor task, supervisor_settings
        end
      end
    end

    def build_proxy settings
      SupervisorProxy.new settings
    end

    def aggrated_status_changed component
      @proxies.each do |proxy|
        proxy.send_aggregated_status component
      end
    end

    def connect_to_supervisor task, supervisor_settings
      proxy = build_proxy({
        site: self,
        task: @task,
        settings: @site_settings, 
        ip: supervisor_settings['ip'],
        port: supervisor_settings['port'],
        logger: @logger,
        archive: @archive
      })
      @proxies << proxy
      run_site_proxy task, proxy
    ensure
      @proxies.delete proxy
    end

    def run_site_proxy task, proxy
      loop do
        proxy.run       # run until disconnected
      rescue IOError => e
        log "Stream error: #{e}", level: :warning
      rescue SystemCallError => e # all ERRNO errors
        log "Reader exception: #{e.to_s}", level: :error
      rescue StandardError => e
        log ["Reader exception: #{e}",e.backtrace].flatten.join("\n"), level: :error
      ensure
        begin
          if @site_settings["reconnect_interval"] != :no
            # sleep until waken by reconnect() or the reconnect interval passed
            proxy.set_state :wait_for_reconnect
            task.with_timeout(@site_settings["reconnect_interval"]) do
              @sleep_condition.wait
            end
          else
            proxy.set_state :cannot_connect
            break
          end
        rescue Async::TimeoutError
          # ignore
        end
      end
    end

    def stop
      log "Stopping site #{@site_settings["site_id"]}", level: :info
      @proxies.each do |proxy|
        proxy.stop
      end
      @proxies.clear
      super
    end
 
    def starting
      log "Starting site #{@site_settings["site_id"]}",
          level: :info,
          timestamp: RSMP.now_object
    end

    def alarm
      @proxies.each do |proxy|
        proxy.stop
      end
    end

  end
end