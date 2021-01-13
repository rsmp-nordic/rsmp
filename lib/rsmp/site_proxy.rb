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
      log "Connection to site #{@site_id} established", level: :info
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
      log "Received Version message for site #{@site_id} using RSMP #{@rsmp_version}", message: message, level: :log
      start_timer
      acknowledge message
      send_version @site_id, @settings['rsmp_versions']
      @version_determined = true

      if @settings['sites']
        @site_settings = @settings['sites'][@site_id]
        @site_settings =@settings['sites'][:any] unless @site_settings
        if @site_settings
          setup_components @site_settings['components']
        end
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

    def aggrated_status_changed component
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
        send_message message
        return message, task.wait
      else
        send_message message
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
        send_message message
        return message, task.wait
      else
        send_message message
        message
      end
    end

    def unsubscribe_to_status component, status_list
      raise NotReady unless ready?
      message = RSMP::StatusUnsubscribe.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => status_list
      })
      send_message message
      message
    end

    def process_status_update message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def send_alarm_acknowledgement component, alarm_code
      message = RSMP::AlarmAcknowledged.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "aCId" => alarm_code,
          "xACId" => '',
          "xNACId" => '',
          "aSp" => 'Acknowledge'
      })
      send_message message
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
        send_message message
        return message, task.wait
      else
        send_message message
        message
      end
    end

    def set_watchdog_interval interval
      @settings["watchdog_interval"] = interval
    end

    def check_sxl_version message
      # store sxl version requested by site
      # TODO should check agaist site settings
      @site_sxl_version = message.attribute 'SXL'
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
      site_ids_changed
    end

  end
end
