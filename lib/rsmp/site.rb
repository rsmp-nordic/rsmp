# RSMP site
# The site initializes the connection to the supervisor.
# Connections to supervisors are handles via supervisor proxies.

module RSMP
  class Site < Node
    include Components

    attr_reader :core_versions, :site_settings, :logger, :proxies

    def initialize options={}
      super options
      initialize_components
      handle_site_settings options
      @proxies = []
      @sleep_condition = Async::Notification.new
      @proxies_condition = Async::Notification.new
      build_proxies
    end

    def sxl_version
      @site_settings['sxl_version']
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
        'core_versions' => 'all',
        'sxl' => 'tlc',
        'sxl_version' => RSMP::Schema.latest_version(:tlc),
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
          'main' => {
            'C1' => {}
          }
        }
      }
      # only one main component can be defined, so replace the default if options define one
      if options.dig(:site_settings,'components','main')
        defaults['components']['main'] = options[:site_settings]['components']['main']
      end

      @site_settings = defaults.deep_merge options[:site_settings]
      check_sxl_version
      setup_components @site_settings['components']
    end

    def check_sxl_version
      sxl = @site_settings['sxl']
      version = @site_settings['sxl_version'].to_s
      RSMP::Schema::find_schema! sxl, version, lenient: true
    end

    def run
      log "Starting site #{@site_settings["site_id"]}",
          level: :info,
          timestamp: @clock.now
      @proxies.each { |proxy| proxy.start }
      @proxies.each { |proxy| proxy.wait }
    end

    def build_proxies
      @site_settings["supervisors"].each do |supervisor_settings|
        @proxies << SupervisorProxy.new({
          site: self,
          task: @task,
          settings: @site_settings,
          ip: supervisor_settings['ip'],
          port: supervisor_settings['port'],
          logger: @logger,
          archive: @archive,
          collect: @collect
        })
      end
    end

    def aggregated_status_changed component, options={}
      @proxies.each do |proxy|
        proxy.send_aggregated_status component, options if proxy.ready?
      end
    end

    def alarm_acknowledged alarm_state
      alarm = AlarmIssue.new( alarm_state.to_hash.merge('aSp' => 'Issue') )
      send_alarm alarm
    end

    def alarm_suspended_or_resumed alarm_state
      alarm = AlarmIssue.new( alarm_state.to_hash.merge('aSp' => 'Suspend') )
      send_alarm alarm
    end

    def alarm_activated_or_deactivated alarm_state
      alarm = AlarmIssue.new( alarm_state.to_hash.merge('aSp' => 'Issue') )
      send_alarm alarm
    end

    def send_alarm alarm
      @proxies.each do |proxy|
        proxy.send_message alarm if proxy.ready?
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
        archive: @archive,
        collect: @collect
      })
      @proxies << proxy
      proxy.start
      @proxies_condition.signal
    end

    # stop
    def stop
      log "Stopping site #{@site_settings["site_id"]}", level: :info
      super
    end

    def wait_for_supervisor ip, timeout
      supervisor = find_supervisor ip
      return supervisor if supervisor
      wait_for_condition(@proxy_condition,timeout:timeout) { find_supervisor ip }
    rescue Async::TimeoutError
      raise RSMP::TimeoutError.new "Supervisor '#{ip}' did not connect within #{timeout}s"
    end

    def find_supervisor ip
      @proxies.each do |supervisor|
        return supervisor if ip == :any || supervisor.ip == ip
      end
      nil
    end

    def build_component id:, type:, settings:
      settings ||= {}
      if type == 'main'
        Component.new id:id, node: self, grouped: true,
          ntsOId: settings['ntsOId'], xNId: settings['xNId']
      else
        Component.new id:id, node: self, grouped: false
      end
    end
  end
end