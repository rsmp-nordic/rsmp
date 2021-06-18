# Handles a supervisor connection to a remote client

module RSMP  
  class SiteProxy < Proxy
    include Components
    include SiteProxyWait

    attr_reader :supervisor, :site_id

    def initialize options
      super options
      initialize_components
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone
      @site_id = nil
    end

    def inspect
      "#<#{self.class.name}:#{self.object_id}, #{inspector(
        :@acknowledgements,:@settings,:@site_settings,:@components
        )}>"
    end
    def node
      supervisor
    end

    def start
      super
      start_reader
    end

    def stop
      log "Closing connection to site", level: :info
      super
    end

    def connection_complete
      super
       sanitized_sxl_version = RSMP::Schemer.sanitize_version(@site_sxl_version)
      log "Connection to site #{@site_id} established, using core #{@rsmp_version}, #{@sxl} #{sanitized_sxl_version}", level: :info
    end

    def process_message message
      case message
        when CommandRequest
        when StatusRequest
        when StatusSubscribe
        when StatusUnsubscribe
          will_not_handle message
        when AggregatedStatus
          process_aggregated_status message
        when AggregatedStatusRequest
          will_not_handle message
        when Alarm
          process_alarm message
        when CommandResponse
          process_command_response message
        when StatusResponse
          process_status_response message
        when StatusUpdate
          process_status_update message
        else
          super message
      end
    end

    def process_command_response message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def process_deferred
      supervisor.process_deferred
    end

    def version_accepted message
      log "Received Version message for site #{@site_id}", message: message, level: :log
      start_timer
      acknowledge message
      send_version @site_id, rsmp_versions
      @version_determined = true

    end

    def request_aggregated_status component, options={}
      raise NotReady unless ready?
      m_id = options[:m_id] || RSMP::Message.make_m_id

      message = RSMP::AggregatedStatusRequest.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "mId" => m_id
      })
      if options[:collect]
        result = nil
        task = @task.async do |task|
          wait_for_aggregated_status task, options[:collect], m_id
        end
        send_message message, validate: options[:validate]
        return message, task.wait
      else
        send_message message, validate: options[:validate]
        message
      end
    end

    def validate_aggregated_status  message, se
      unless se && se.is_a?(Array) && se.size == 8
        reason = "invalid AggregatedStatus, 'se' must be an Array of size 8"
        dont_acknowledge message, "Received", reaons
        raise InvalidMessage
      end
    end

    def process_aggregated_status message
      se = message.attribute("se")
      validate_aggregated_status(message,se) == false
      c_id = message.attributes["cId"]
      component = @components[c_id]
      if component == nil
        if @site_settings == nil || @site_settings['components'] == nil
          component = build_component(id:c_id, type:nil)
          @components[c_id] = component
          log "Adding component #{c_id} to site #{@site_id}", level: :info
        else
          reason = "component #{c_id} not found"
          dont_acknowledge message, "Ignoring #{message.type}:", reason
          return
        end
      end

      component.set_aggregated_status_bools se
      log "Received #{message.type} status for component #{c_id} [#{component.aggregated_status.join(', ')}]", message: message
      acknowledge message
    end

    def aggregated_status_changed component, options={}
      @supervisor.aggregated_status_changed self, component
    end

    def process_alarm message
      alarm_code = message.attribute("aCId")
      asp = message.attribute("aSp")
      status = ["ack","aS","sS"].map { |key| message.attribute(key) }.join(',')
      log "Received #{message.type}, #{alarm_code} #{asp} [#{status}]", message: message, level: :log
      acknowledge message
    end

    def version_acknowledged
      connection_complete
    end

    def process_watchdog message
      super
      if @watchdog_started == false
        start_watchdog
      end
    end

    def site_ids_changed
      @supervisor.site_ids_changed
    end

    def request_status component, status_list, options={}
      raise NotReady unless ready?
      m_id = options[:m_id] || RSMP::Message.make_m_id

      # additional items can be used when verifying the response,
      # but must to remove from the request
      request_list = status_list.map { |item| item.slice('sCI','n') }

      message = RSMP::StatusRequest.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => request_list,
          "mId" => m_id
      })
      if options[:collect]
        result = nil
        task = @task.async do |task|
          collect_options = options[:collect].merge status_list: status_list
          collect_status_responses task, collect_options, m_id
        end
        send_message message, validate: options[:validate]

        # task.wait return the result of the task. if the task raised an exception
        # it will be reraised. but that mechanish does not work if multiple values
        # are returned. so manually raise if first element is an exception
        result = task.wait
        raise result.first if result.first.is_a? Exception
        return message, *result
      else
        send_message message, validate: options[:validate]
        message
      end
    end

    def process_status_response message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def subscribe_to_status component, status_list, options={}
      raise NotReady unless ready?
      m_id = options[:m_id] || RSMP::Message.make_m_id
      
      # additional items can be used when verifying the response,
      # but must to remove from the subscribe message
      subscribe_list = status_list.map { |item| item.slice('sCI','n','uRt') }

      message = RSMP::StatusSubscribe.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => subscribe_list,
          'mId' => m_id
      })
      if options[:collect]
        result = nil
        task = @task.async do |task|
          collect_options = options[:collect].merge status_list: status_list
          collect_status_updates task, collect_options, m_id
        end
        send_message message, validate: options[:validate]

        # task.wait return the result of the task. if the task raised an exception
        # it will be reraised. but that mechanish does not work if multiple values
        # are returned. so manually raise if first element is an exception
        result = task.wait
        raise result.first if result.first.is_a? Exception
        return message, *result
      else
        send_message message, validate: options[:validate]
        message
      end
    end

    def unsubscribe_to_status component, status_list, options={}
      raise NotReady unless ready?
      message = RSMP::StatusUnsubscribe.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => status_list
      })
      send_message message, validate: options[:validate]
      message
    end

    def process_status_update message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def send_alarm_acknowledgement component, alarm_code, options={}
      message = RSMP::AlarmAcknowledged.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "aCId" => alarm_code,
          "xACId" => '',
          "xNACId" => '',
          "aSp" => 'Acknowledge'
      })
      send_message message, validate: options[:validate]
      message
    end

    def send_command component, command_list, options={}
      raise NotReady unless ready?
      m_id = options[:m_id] || RSMP::Message.make_m_id
      message = RSMP::CommandRequest.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "arg" => command_list,
          "mId" => m_id
      })
      if options[:collect]
        result = nil
        task = @task.async do |task|
          collect_options = options[:collect].merge command_list: command_list
          collect_command_responses task, collect_options, m_id
        end
        send_message message, validate: options[:validate]

        # task.wait return the result of the task. if the task raised an exception
        # it will be reraised. but that mechanish does not work if multiple values
        # are returned. so manually raise if first element is an exception
        result = task.wait
        raise result.first if result.first.is_a? Exception
        return message, *result
      else
        send_message message, validate: options[:validate]
        message
      end
    end

    def set_watchdog_interval interval
      @settings['intervals']['watchdog'] = interval
    end

    def check_sxl_version message

      # check that we have a schema for specified sxl type and version
      # note that the type comes from the site config, while the version
      # comes from the Version message send by the site
      type = 'tlc'
      version = message.attribute 'SXL'
      RSMP::Schemer::find_schema! type, version, lenient: true

      # store sxl version requested by site
      # TODO should check agaist site settings
      @site_sxl_version = message.attribute 'SXL'
    rescue RSMP::Schemer::UnknownSchemaError => e
      dont_acknowledge message, "Rejected #{message.type} message,", "#{e}"
    end

    def sxl_version
      # a supervisor does not maintain it's own sxl version
      # instead we use what the site requests
      @site_sxl_version
    end

    def process_version message
      return extraneous_version message if @version_determined
      check_site_ids message
      check_rsmp_version message
      check_sxl_version message
      version_accepted message
    end

    def check_site_ids message
      # RSMP support multiple site ids. we don't support this yet. instead we use the first id only
      site_id = message.attribute("siteId").map { |item| item["sId"] }.first
      @supervisor.check_site_id site_id
      @site_id = site_id
      setup_site_settings
      site_ids_changed
    end

    def find_site_settings site_id
      if @settings['sites'] && @settings['sites'][@site_id]
        log "Using site settings for site id #{@site_id}", level: :debug
        return @settings['sites'][@site_id]
      end

      settings = @settings['guest']
      if @settings['guest']
        log "Using site settings for guest", level: :debug
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

    def notify_error e, options={}
      @supervisor.notify_error e, options if @supervisor
    end

  end
end
