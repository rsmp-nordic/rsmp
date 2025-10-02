# Handles a supervisor connection to a remote client

module RSMP
  class SiteProxy < Proxy
    include Components
    include Modules::StatusHandling
    include Modules::AggregatedStatusHandling
    include Modules::AlarmHandling
    include Modules::CommandHandling

    attr_reader :supervisor, :site_id

    def initialize(options)
      super(options.merge(node: options[:supervisor]))
      initialize_components
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone
      @site_id = options[:site_id]
      @status_subscriptions = {}
    end

    # handle communication
    # when we're created, the socket is already open
    def run
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

    def revive(options)
      super
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone
    end

    def inspect
      "#<#{self.class.name}:#{object_id}, #{inspector(
        :@acknowledgements, :@settings, :@site_settings, :@components
      )}>"
    end

    def node
      supervisor
    end

    def handshake_complete
      super
      sanitized_sxl_version = RSMP::Schema.sanitize_version(@site_sxl_version)
      log "Connection to site #{@site_id} established, using core #{@core_version}, #{@sxl} #{sanitized_sxl_version}",
          level: :info
      start_watchdog
    end

    def process_message(message)
      return super if handled_by_parent?(message)

      case message
      when StatusUnsubscribe, AggregatedStatusRequest
        will_not_handle message
      when AggregatedStatus
        process_aggregated_status message
      when AlarmIssue, AlarmSuspended, AlarmResumed, AlarmAcknowledged
        process_alarm message
      when CommandResponse
        process_command_response message
      when StatusResponse
        process_status_response message
      when StatusUpdate
        process_status_update message
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

    def version_accepted(message)
      log "Received Version message for site #{@site_id}", message: message, level: :log
      start_timer
      acknowledge message
      send_version @site_id, core_versions
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
        handshake_complete
      end
    end

    def validate_ready(action)
      raise NotReady, "Can't #{action} because connection is not ready. (Currently #{@state})" unless ready?
    end

    def version_acknowledged; end

    def site_ids_changed
      @supervisor.site_ids_changed
    end

    def watchdog_interval=(interval)
      @settings['intervals']['watchdog'] = interval
    end

    def check_sxl_version(message)
      # check that we have a schema for specified sxl type and version
      # note that the type comes from the site config, while the version
      # comes from the Version message send by the site
      type = @site_settings['sxl']
      version = message.attribute 'SXL'
      RSMP::Schema.find_schema! type, version, lenient: true

      # store sxl version requested by site
      # TODO should check agaist site settings
      @site_sxl_version = message.attribute 'SXL'
    rescue RSMP::Schema::UnknownSchemaError => e
      dont_acknowledge message, "Rejected #{message.type} message,", e.to_s
    end

    def sxl_version
      # a supervisor does not maintain it's own sxl version
      # instead we use what the site requests
      @site_sxl_version
    end

    def process_version(message)
      return extraneous_version message if @version_determined

      check_site_ids message
      check_sxl_version message
      version_accepted message
    end

    def check_site_ids(message)
      # RSMP support multiple site ids. we don't support this yet. instead we use the first id only
      site_id = message.attribute('siteId').map { |item| item['sId'] }.first
      @supervisor.check_site_id site_id
      site_ids_changed
    end

    def find_site_settings(_site_id)
      if @settings['sites'] && @settings['sites'][@site_id]
        log "Using site settings for site id #{@site_id}", level: :debug
        return @settings['sites'][@site_id]
      end

      @settings['guest']
      if @settings['guest']
        log 'Using site settings for guest', level: :debug
        return @settings['guest']
      end

      nil
    end

    def setup_site_settings
      @site_settings = find_site_settings @site_id
      if @site_settings
        @sxl = @site_settings['sxl']
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
        ComponentProxy.new id: id, node: self, grouped: true,
                           ntsoid: settings['ntsOId'], xnid: settings['xNId']
      else
        ComponentProxy.new id: id, node: self, grouped: false
      end
    end

    def infer_component_type(_component_id)
      ComponentProxy
    end
  end
end
