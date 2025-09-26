# Handles a supervisor connection to a remote client

module RSMP
  class SiteProxy < Proxy
    include Components

    attr_reader :supervisor, :site_id

    def initialize options
      super options.merge(node:options[:supervisor])
      initialize_components
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone
      @site_id = options[:site_id]
      @status_subscriptions = {}
    end

    # handle communication
    # when we're created, the socket is already open
    def run
      set_state :connected
      start_reader
      wait_for_reader   # run until disconnected
    rescue RSMP::ConnectionError => e
      log e, level: :error
    rescue StandardError => e
      distribute_error e, level: :internal
    ensure
      close
    end

    def revive options
      super options
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone
    end

    def inspect
      "#<#{self.class.name}:#{self.object_id}, #{inspector(
        :@acknowledgements,:@settings,:@site_settings,:@components
        )}>"
    end

    def node
      supervisor
    end

    def handshake_complete
      super
      sanitized_sxl_version = RSMP::Schema.sanitize_version(@site_sxl_version)
      log "Connection to site #{@site_id} established, using core #{@core_version}, #{@sxl} #{sanitized_sxl_version}", level: :info
      start_watchdog
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
        when AlarmIssue, AlarmSuspended, AlarmResumed, AlarmAcknowledged
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
    rescue RSMP::RepeatedAlarmError, RSMP::RepeatedStatusError, RSMP::TimestampError => e
      str = "Rejected #{message.type} message,"
      dont_acknowledge message, str, "#{e}"
      distribute_error e.exception("#{str}#{e.message} #{message.json}")
    end

    def process_command_response message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def version_accepted message
      log "Received Version message for site #{@site_id}", message: message, level: :log
      start_timer
      acknowledge message
      send_version @site_id, core_versions
      @version_determined = true
    end

    def acknowledged_first_ingoing message
      case message.type
      when "Watchdog"
        send_watchdog
      end
    end

    def acknowledged_first_outgoing message
      case message.type
      when "Watchdog"
        handshake_complete
      end
    end

    def validate_ready action
      raise NotReady.new("Can't #{action} because connection is not ready. (Currently #{@state})") unless ready?
    end

    def request_aggregated_status component, options={}
      validate_ready 'request aggregated status'
      m_id = options[:m_id] || RSMP::Message.make_m_id
      message = RSMP::AggregatedStatusRequest.new({
        "cId" => component,
        "mId" => m_id
      })
      set_nts_message_attributes message
      send_and_optionally_collect message, options do |collect_options|
        AggregatedStatusCollector.new(
          self,
          collect_options.merge(task:@task,m_id: m_id, num:1)
        )
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
      validate_aggregated_status(message,se)
      c_id = message.attributes["cId"]
      component = find_component c_id
      unless component
        reason = "component #{c_id} not found"
        dont_acknowledge message, "Ignoring #{message.type}:", reason
        return
      end

      component.set_aggregated_status_bools se
      log "Received #{message.type} status for component #{c_id} [#{component.aggregated_status.join(', ')}]", message: message
      acknowledge message
    end

    def aggregated_status_changed component, options={}
      @supervisor.aggregated_status_changed self, component
    end

    def process_alarm message
      component = find_component message.attribute("cId")
      status = ["ack","aS","sS"].map { |key| message.attribute(key) }.join(',')
      component.handle_alarm message
      alarm_code = message.attribute("aCId")
      asp = message.attribute("aSp")
      log "Received #{message.type}, #{alarm_code} #{asp} [#{status}]", message: message, level: :log
      acknowledge message
    end

    def version_acknowledged
    end

    def process_watchdog message
      super
    end

    def site_ids_changed
      @supervisor.site_ids_changed
    end

    def request_status component, status_list, options={}
      validate_ready 'request status'
      m_id = options[:m_id] || RSMP::Message.make_m_id

      # additional items can be used when verifying the response,
      # but must be removed from the request
      request_list = status_list.map { |item| item.slice('sCI','n') }

      message = RSMP::StatusRequest.new({
          "cId" => component,
          "sS" => request_list,
          "mId" => m_id
      })
      set_nts_message_attributes message
      send_and_optionally_collect message, options do |collect_options|
        StatusCollector.new(
          self,
          status_list,
          collect_options.merge(task:@task,m_id: m_id)
          )
      end
    end

    def process_status_response message
      component = find_component message.attribute("cId")
      component.store_status message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def subscribe_to_status component_id, status_list, options={}
      validate_ready 'subscribe to status'
      m_id = options[:m_id] || RSMP::Message.make_m_id

      # additional items can be used when verifying the response,
      # but must be removed from the subscribe message
      subscribe_list = status_list.map { |item| item.slice('sCI','n','uRt','sOc') }

      # update our subcription list
      @status_subscriptions[component_id] ||= {}
      subscribe_list.each do |item|
        sCI = item["sCI"]
        n = item["n"]
        uRt = item["uRt"]
        sOc = item["sOc"]
        @status_subscriptions[component_id][sCI] ||= {}
        @status_subscriptions[component_id][sCI][n] ||= {}
        @status_subscriptions[component_id][sCI][n]['uRt'] = uRt
        @status_subscriptions[component_id][sCI][n]['sOc'] = sOc
      end

      component = find_component component_id

      message = RSMP::StatusSubscribe.new({
          "cId" => component_id,
          "sS" => subscribe_list,
          'mId' => m_id
      })
      set_nts_message_attributes message

      send_and_optionally_collect message, options do |collect_options|
        StatusCollector.new(
          self,
          status_list,
          collect_options.merge(task:@task,m_id: m_id)
        )
      end
    end

    def unsubscribe_to_status component_id, status_list, options={}
      validate_ready 'unsubscribe to status'

      # update our subcription list
      status_list.each do |item|
        sCI = item["sCI"]
        n = item["n"]
        if @status_subscriptions.dig(component_id,sCI,n)
          @status_subscriptions[component_id][sCI].delete n
          @status_subscriptions[component_id].delete(sCI) if @status_subscriptions[component_id][sCI].empty?
          @status_subscriptions.delete(component_id) if @status_subscriptions[component_id].empty?
        end
      end

      message = RSMP::StatusUnsubscribe.new({
        "cId" => component_id,
        "sS" => status_list
      })
      set_nts_message_attributes message
      send_message message, validate: options[:validate]
      message
    end

    def process_status_update message
      component = find_component message.attribute("cId")
      component.check_repeat_values message, @status_subscriptions
      component.store_status message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def send_alarm_acknowledgement component, alarm_code, options={}
      message = RSMP::AlarmAcknowledged.new({
          "cId" => component,
          "aCId" => alarm_code,
      })
      send_message message, validate: options[:validate]
      message
    end

    def send_command component, command_list, options={}
      validate_ready 'send command'
      m_id = options[:m_id] || RSMP::Message.make_m_id
      message = RSMP::CommandRequest.new({
          "cId" => component,
          "arg" => command_list,
          "mId" => m_id
      })
      set_nts_message_attributes message
      send_and_optionally_collect message, options do |collect_options|
        CommandResponseCollector.new(
          self,
          command_list,
          collect_options.merge(task:@task,m_id: m_id)
          )
      end
    end

    def set_watchdog_interval interval
      @settings['intervals']['watchdog'] = interval
    end

    def check_sxl_version message
      # check that we have a schema for specified sxl type and version
      # note that the type comes from the site config, while the version
      # comes from the Version message send by the site
      type = @site_settings['sxl']
      version = message.attribute 'SXL'
      RSMP::Schema::find_schema! type, version, lenient: true

      # store sxl version requested by site
      # TODO should check agaist site settings
      @site_sxl_version = message.attribute 'SXL'
    rescue RSMP::Schema::UnknownSchemaError => e
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
      check_sxl_version message
      version_accepted message
    end

    def check_site_ids message
      # RSMP support multiple site ids. we don't support this yet. instead we use the first id only
      site_id = message.attribute("siteId").map { |item| item["sId"] }.first
      @supervisor.check_site_id site_id
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

    def receive_error e, options={}
      @supervisor.receive_error e, options if @supervisor
      distribute_error e, options
    end

    def build_component id:, type:, settings:{}
      settings ||= {}
      if type == 'main'
        ComponentProxy.new id:id, node: self, grouped: true,
          ntsOId: settings['ntsOId'], xNId: settings['xNId']
      else
        ComponentProxy.new id:id, node: self, grouped: false
      end
    end

    def infer_component_type component_id
      ComponentProxy
    end

    # Unsubscribe from all subscriptions
    # This method provides a centralized way to clean up all subscriptions
    def unsubscribe_all
      @status_subscriptions.each do |component_id, component_subscriptions|
        component_subscriptions.each do |sCI, sCI_subscriptions|
          sCI_subscriptions.each do |n, _subscription_data|
            status_list = [{ 'sCI' => sCI, 'n' => n }]
            begin
              unsubscribe_to_status component_id, status_list
            rescue => e
              log "Failed to unsubscribe from #{component_id} #{sCI}/#{n}: #{e.message}", level: :warn
            end
          end
        end
      end
    end
  end
end
