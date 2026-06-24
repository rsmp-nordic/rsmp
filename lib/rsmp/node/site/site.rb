module RSMP
  # RSMP site implementation that manages proxies and components.
  class Site < Node
    include Components

    attr_reader :core_version, :site_settings, :logger, :proxies, :ready_condition

    def self.options_class
      RSMP::Site::Options
    end

    def initialize(options = {})
      super
      initialize_components
      handle_site_settings options
      @proxies = []
      @sleep_condition = Async::Notification.new
      @proxies_condition = Async::Notification.new
      @ready_condition = Async::Notification.new
      build_proxies
    end

    def sxls
      @site_settings['sxls']
    end

    def primary_sxl
      sxls.first
    end

    def sxl_version
      primary_sxl && primary_sxl['version']
    end

    def site_id
      @site_settings['site_id']
    end

    def client_role?
      @site_settings['connection_role'] != 'server'
    end

    def server_role?
      @site_settings['connection_role'] == 'server'
    end

    def handle_site_settings(options = {})
      options_class = self.class.options_class
      settings = options[:site_settings] || {}
      settings = denormalize_sxls(settings)
      @site_options = options_class.new(settings)
      @site_settings = @site_options.to_h

      check_sxls
      check_core_versions
      setup_components @site_settings['components']
    end

    def denormalize_sxls(settings)
      sxls = settings['sxls']
      return settings unless sxls.is_a?(Array)

      settings.merge(
        'sxls' => sxls.to_h { |sxl| [sxl['name'], sxl['version']] }
      )
    end

    def check_sxls
      raise RSMP::ConfigurationError, 'No SXLs specified' unless sxls

      sxls.each do |sxl|
        name = sxl['name']
        version = sxl['version'].to_s
        raise RSMP::ConfigurationError, 'SXL name cannot be core' if name.to_s == 'core'

        RSMP::Schema.find_schema! name, version, lenient: true
      end
    end

    def check_core_versions
      version = @site_settings['core_version']
      return unless version

      return if RSMP::Schema.core_versions.include? version

      error_str = "Unknown core version: #{version}"
      raise RSMP::ConfigurationError, error_str
    end

    def site_type_name
      'site'
    end

    def log_site_starting
      log "Starting #{site_type_name} #{@site_settings['site_id']}", level: :info, timestamp: @clock.now
      sxl = "Using SXLs #{sxls.map { |item| "#{item['name']} #{item['version']}" }.join(', ')}"
      version = @site_settings['core_version']
      core = if version
               "accepting only core version #{version}"
             else
               "accepting all core versions [#{RSMP::Schema.core_versions.join(', ')}]"
             end
      log "#{sxl}, #{core}", level: :info, timestamp: @clock.now
    end

    def run
      log_site_starting
      start_status_timer
      if server_role?
        listen_for_supervisors
      else
        @proxies.each(&:start)
        @proxies.each(&:wait)
      end
    end

    def build_proxies
      return if server_role?

      @site_settings['supervisors'].each do |supervisor_settings|
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

    def listen_for_supervisors
      ip = @site_settings['ip'] || '0.0.0.0'
      port = @site_settings['port']
      log "Starting #{site_type_name} listener on #{ip}:#{port}", level: :info, timestamp: @clock.now
      @endpoint = IO::Endpoint.tcp(ip, port)
      @accept_task = Async::Task.current.async do |task|
        task.annotate 'site accept loop'
        @endpoint.accept do |socket|
          accept_supervisor_connection socket
        rescue StandardError => e
          distribute_error e, level: :internal
        end
      rescue Async::Stop
        # Expected during shutdown - no action needed
      rescue StandardError => e
        distribute_error e, level: :internal
      end

      @ready_condition.signal
      @accept_task.wait
    end

    def accept_supervisor_connection(socket)
      remote_port = socket.remote_address.ip_port
      remote_ip = socket.remote_address.ip_address
      info = { ip: remote_ip, port: remote_port, hostname: remote_ip, now: Clock.now }
      stream = IO::Stream::Buffered.new(socket)
      proxy = SupervisorProxy.new({
                                    site: self,
                                    task: @task,
                                    settings: @site_settings,
                                    socket: socket,
                                    stream: stream,
                                    protocol: RSMP::Protocol.new(stream),
                                    ip: remote_ip,
                                    port: remote_port,
                                    info: info,
                                    logger: @logger,
                                    archive: @archive,
                                    collect: @collect
                                  })
      @proxies << proxy
      @proxies_condition.signal
      proxy.start
      proxy.wait
    end

    def aggregated_status_changed(component, _options = {})
      @proxies.each do |proxy|
        proxy.send_aggregated_status component
      end
    end

    def alarm_acknowledged(alarm_state)
      send_alarm AlarmAcknowledged.new(alarm_state.to_hash)
    end

    def alarm_suspended_or_resumed(alarm_state)
      send_alarm AlarmSuspended.new(alarm_state.to_hash)
    end

    def alarm_activated_or_deactivated(alarm_state)
      send_alarm AlarmIssue.new(alarm_state.to_hash)
    end

    def send_alarm(alarm)
      @proxies.each do |proxy|
        proxy.send_message alarm if proxy.receive_alarms?
      end
    end

    def start_status_timer
      return if @status_timer

      interval = @site_settings['intervals']['timer'] || 1
      log "Starting site status timer with interval #{interval} seconds", level: :debug
      @status_timer = @task.async do |task|
        task.annotate 'site status timer'
        run_status_timer task, interval
      end
    end

    def run_status_timer(task, interval)
      next_time = Time.now.to_f
      loop do
        now = Clock.now
        tick_status_subscriptions now
      rescue StandardError => e
        distribute_error e, level: :internal
      ensure
        next_time += interval
        duration = next_time - Time.now.to_f
        task.sleep duration
      end
    end

    def tick_status_subscriptions(now)
      @proxies.each { |proxy| proxy.status_update_timer now }
    end

    def stop_status_timer
      @status_timer&.stop
    ensure
      @status_timer = nil
    end

    def stop_subtasks
      stop_status_timer
      @accept_task&.stop
      @accept_task = nil
      @endpoint = nil
      super
    end

    def connect_to_supervisor(_task, supervisor_settings)
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
      log "Stopping site #{@site_settings['site_id']}", level: :info
      super
    end

    def wait_for_supervisor(ip, timeout:)
      supervisor = find_supervisor ip
      return supervisor if supervisor

      wait_for_condition(@proxies_condition, timeout: timeout) { find_supervisor ip }
    rescue Async::TimeoutError
      raise RSMP::TimeoutError, "Supervisor '#{ip}' did not connect within #{timeout}s"
    end

    def find_supervisor(ip)
      @proxies.each do |supervisor|
        return supervisor if ip == :any || supervisor.ip == ip
      end
      nil
    end

    def build_component(id:, type:, settings:)
      settings ||= {}
      if type == 'main'
        Component.new id: id, node: self, type: type, name: settings['name'], grouped: true,
                      ntsoid: settings['ntsOId'], xnid: settings['xNId']
      else
        Component.new id: id, node: self, type: type, name: settings['name'], grouped: false
      end
    end
  end
end
