# RSMP site
# The site initializes the connection to the supervisor.
# Connections to supervisors are handles via supervisor proxies.

module RSMP
  class Site < Node
    include Components

    attr_reader :rsmp_versions, :site_settings, :logger, :proxies

    def initialize options={}
      initialize_components
      handle_site_settings options
      super options
      @proxies = []
      @sleep_condition = Async::Notification.new
    end

    def site_id
      @site_settings['site_id']
    end

    def handle_site_settings options={}
      defaults = {
        'site_id' => 'RN+SI0001',
        'supervisors' => [
          { 'ip' => '127.0.0.1', 'port' => 12111 }
        ],
        'rsmp_versions' => 'all',
        'sxl' => 'tlc',
        'sxl_version' => '1.0.15',
        'intervals' => {
          'timer' => 0.1,
          'watchdog' => 1,
          'reconnect' => 0.1
        },
        'timeouts' => {
          'watchdog' => 2,
          'acknowledgement' => 2
        },
        'send_after_connect' => true,
        'components' => {
          'C1' => {}
        }
      }
      
      @site_settings = defaults.deep_merge options[:site_settings]
      check_sxl_version
      setup_components @site_settings['components']
    end

    def check_sxl_version
      sxl = @site_settings['sxl']
      version = @site_settings['sxl_version']
      RSMP::Schemer::find_schema! sxl, version
    end

    def reconnect
      @sleep_condition.signal
    end

    def start_action
      @site_settings["supervisors"].each do |supervisor_settings|
        @task.async do |task|
          task.annotate "site proxy"
          connect_to_supervisor task, supervisor_settings
        rescue StandardError => e
          notify_error e, level: :internal
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
      rescue StandardError => e
        notify_error e, level: :internal
      ensure
        begin
          if @site_settings['intervals']['watchdog'] != :no
            # sleep until waken by reconnect() or the reconnect interval passed
            proxy.set_state :wait_for_reconnect
            task.with_timeout(@site_settings['intervals']['watchdog']) do
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
          timestamp: @clock.now
    end

    def alarm
      @proxies.each do |proxy|
        proxy.stop
      end
    end

  end
end