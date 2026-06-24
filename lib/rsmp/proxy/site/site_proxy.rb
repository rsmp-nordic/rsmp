module RSMP
  # Handles a supervisor-side proxy for a connected site.
  class SiteProxy < Proxy
    include Components
    include Modules::Status
    include Modules::AggregatedStatus
    include Modules::Alarms
    include Modules::Commands
    include SiteSxlSelection

    attr_reader :supervisor, :site_id

    def initialize(options)
      super(options.merge(node: options[:supervisor]))
      initialize_components
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone
      @site_id = options[:site_id]
      @configured_site_settings = options[:site_settings]
      @status_subscriptions = {}
    end

    # handle communication
    # when we're created, the socket is already open
    def run
      if @protocol
        run_accepted_connection
      else
        run_outbound_connection
      end
    end

    def run_accepted_connection
      self.state = :connected
      start_reader
      wait_for_reader # run until disconnected
    rescue RSMP::ConnectionError => e
      log e, level: :error
    rescue StandardError => e
      distribute_error e, level: :internal
    ensure
      close
    end

    def run_outbound_connection
      loop do
        setup_site_settings
        connect
        start_reader
        wait_for_reader
        break unless reconnect_delay?
      rescue Restart
        @logger.mute @ip, @port
        raise
      rescue RSMP::ConnectionError => e
        log e, level: :error
        break unless reconnect_delay?
      rescue StandardError => e
        distribute_error e, level: :internal
        break unless reconnect_delay?
      ensure
        close
        stop_subtasks
      end
    end

    def connect
      log "Connecting to site #{@site_id} at #{@ip}:#{@port}", level: :info
      self.state = :connecting
      endpoint = IO::Endpoint.tcp(@ip, @port)
      timeout = @site_settings.dig('timeouts', 'connect') || 1.1
      task.with_timeout timeout do
        @socket = endpoint.connect
      end
      @stream = IO::Stream::Buffered.new(@socket)
      @protocol = RSMP::Protocol.new(@stream)
      self.state = :connected
      @logger.unmute @ip, @port
      log "Connected to site #{@site_id} at #{@ip}:#{@port}", level: :info
    rescue SystemCallError => e
      raise ConnectionError, "Could not connect to site #{@site_id} at #{@ip}:#{@port}: Errno #{e.errno} #{e}"
    rescue StandardError => e
      raise ConnectionError, "Error while connecting to site #{@site_id} at #{@ip}:#{@port}: #{e}"
    end

    def reconnect_delay?
      return false if @site_settings['intervals']['reconnect'] == :no

      interval = @site_settings['intervals']['reconnect'] || 0.1
      log "Will try to reconnect again every #{interval} seconds...", level: :info
      @logger.mute @ip, @port
      @task.sleep interval
      true
    end

    def revive(options)
      super
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone
      @configured_site_settings = options[:site_settings]
    end

    def node
      supervisor
    end

    def handshake_complete
      super
      sxl_summary = accepted_sxls.map { |item| "#{item['name']} #{item['version']}" }.join(', ')
      log "Connection to site #{@site_id} established, using core #{@core_version}, SXLs [#{sxl_summary}]",
          level: :info
      start_watchdog
    end

    def process_message(message)
      return super if handled_by_parent?(message)

      case message
      when StatusUnsubscribe, AggregatedStatusRequest
        will_not_handle message
      when ComponentList
        process_component_list message
      when AggregatedStatus
        process_aggregated_status message
      when AlarmIssue, AlarmSuspended, AlarmResumed, AlarmAcknowledged,
           CommandResponse, StatusResponse, StatusUpdate
        handle_interface_message message
      else
        super
      end
    rescue RSMP::RepeatedAlarmError, RSMP::RepeatedStatusError, RSMP::TimestampError => e
      str = "Rejected #{message.type} message,"
      dont_acknowledge message, str, e.to_s
      distribute_error e.exception("#{str}#{e.message} #{message.json}")
    end

    def handled_by_parent?(message)
      message.is_a?(CommandRequest) || message.is_a?(StatusRequest) || message.is_a?(StatusSubscribe)
    end

    def handle_interface_message(message)
      interface = sxl_interface_for message
      interface.validate_message! message
      record_interface_message message
      interface.process_message message
    end

    def record_interface_message(message)
      case message
      when AlarmIssue, AlarmSuspended, AlarmResumed, AlarmAcknowledged
        process_alarm message
      when CommandResponse
        process_command_response message
      when StatusResponse
        process_status_response message
      when StatusUpdate
        process_status_update message
      end
    end

    def version_accepted(message)
      log "Received Version message for site #{@site_id}", message: message, level: :log
      start_timer
      acknowledge message
      response_id = core_3_3? ? (@supervisor.site_id || @site_id) : @site_id
      send_version_response response_id, core_versions
      @version_determined = true
    end

    def acknowledged_first_ingoing(message)
      case message.type
      when 'Watchdog'
        send_watchdog
      end
    end

    def acknowledged_first_outgoing(message)
      case message.type
      when 'Watchdog'
        if core_3_3?
          @outgoing_watchdog_acknowledged = true
          handshake_complete if @component_list_received
        else
          handshake_complete
        end
      end
    end

    def validate_ready(action)
      raise NotReady, "Can't #{action} because connection is not ready. (Currently #{@state})" unless ready?
    end

    def version_acknowledged; end

    def process_component_list(message)
      log "Received #{message.type}", message: message, level: :log
      rebuild_components_from_list message.attributes['components']
      build_sxl_interfaces
      acknowledge message
      @component_list_received = true
      handshake_complete if @outgoing_watchdog_acknowledged
    end

    def rebuild_components_from_list(items)
      main_id = @site_settings.dig('components', 'main')&.keys&.first
      @components = {}
      @main = nil
      items.each do |item|
        grouped = item['id'] == main_id
        component = ComponentProxy.new(
          id: item['id'],
          node: self,
          type: item['type'],
          name: item['name'],
          grouped: grouped
        )
        @components[component.c_id] = component
        @main = component if grouped
      end
    end

    def site_ids_changed
      @supervisor.site_ids_changed
    end

    def watchdog_interval=(interval)
      @settings['intervals']['watchdog'] = interval
    end

    def process_version(message)
      return extraneous_version message if @version_determined

      check_site_ids message
      check_core_version message
      check_sxl_version message
      version_accepted message
    end

    def check_site_ids(message)
      # RSMP support multiple site ids. we don't support this yet. instead we use the first id only
      site_id = message.attribute('siteId').map { |item| item['sId'] }.first
      @site_id ||= site_id
      @supervisor.check_site_id site_id
      site_ids_changed
    end

    def find_site_settings(_site_id)
      base = @settings['default'] || {}

      if @settings['sites']
        site_specific = @settings['sites'][@site_id] || @settings['sites']['default']
        if site_specific
          label = @settings['sites'][@site_id] ? "site id #{@site_id}" : 'default'
          log "Using #{label} site settings", level: :debug
          return base.deep_merge(site_specific)
        end
      end

      unless base.empty?
        log 'Using default site settings', level: :debug
        return base
      end

      nil
    end

    def setup_site_settings
      @site_settings = @configured_site_settings || find_site_settings(@site_id)
      if @site_settings
        @sxls = configured_sxls
        @accepted_sxls = @sxls.dup
        build_sxl_interfaces
        setup_components @site_settings['components']
      else
        dont_acknowledge message, 'Rejected', "No config found for site #{@site_id}"
      end
    end

    def receive_error(error, options = {})
      @supervisor&.receive_error error, options
      distribute_error error, options
    end

    def build_component(id:, type:, settings: {})
      settings ||= {}
      if type == 'main'
        ComponentProxy.new id: id, node: self, type: type, name: settings['name'], grouped: true,
                           ntsoid: settings['ntsOId'], xnid: settings['xNId']
      else
        ComponentProxy.new id: id, node: self, type: type, name: settings['name'], grouped: false
      end
    end

    def infer_component_type(_component_id)
      ComponentProxy
    end
  end
end
