# RSMP site
# The site initializes the connection to the supervisor.
# Connections to supervisors are handles via supervisor proxies.

module RSMP
  class Site < Node
    include Components

    attr_reader :core_version, :site_settings, :logger, :proxies

    def initialize options={}
      super options
      initialize_components
      
      # Use new configuration system
      site_settings = options[:site_settings] || {}
      @site_options = RSMP::Options::SiteOptions.new(site_settings)
      @site_settings = @site_options.to_h  # For backward compatibility
      
      setup_components @site_options.components
      @proxies = []
      @sleep_condition = Async::Notification.new
      @proxies_condition = Async::Notification.new
      build_proxies
    end

    def sxl_version
      @site_options.sxl_version
    end

    def site_id
      @site_options.site_id
    end

    # Deprecated: Configuration handling is now done in SiteOptions
    # This method is kept for backward compatibility but no longer performs validation
    def handle_site_settings options={}
      # Validation and defaults are now handled by SiteOptions in initialize
      # This method is deprecated and will be removed in a future version
    end

    # Deprecated: SXL version validation is now handled by SiteOptions
    def check_sxl_version
      # Validation is now handled by SiteOptions
    end

    # Deprecated: Core version validation is now handled by SiteOptions  
    def check_core_versions
      # Validation is now handled by SiteOptions
    end

    def site_type_name
      "site"
    end

    def log_site_starting
      log "Starting #{site_type_name} #{@site_settings["site_id"]}", level: :info, timestamp: @clock.now
      sxl = "Using #{@site_settings["sxl"]} sxl #{@site_settings["sxl_version"]}"
      version = @site_settings["core_version"]
      unless version
        core = "accepting all core versions [#{RSMP::Schema.core_versions.join(', ')}]"
      else
        core = "accepting only core version #{version}"
      end
      log "#{sxl}, #{core}", level: :info, timestamp: @clock.now
    end

    def run
      log_site_starting
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
      send_alarm AlarmAcknowledged.new( alarm_state.to_hash )
    end

    def alarm_suspended_or_resumed alarm_state
      send_alarm AlarmSuspended.new( alarm_state.to_hash )
    end

    def alarm_activated_or_deactivated alarm_state
      send_alarm AlarmIssue.new( alarm_state.to_hash )
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