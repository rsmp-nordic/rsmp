# Handles a supervisor connection to a remote client

module RSMP  
  class SiteProxy < Proxy
    include SiteBase

    attr_reader :supervisor

    def initialize options
      super options
      initialize_site
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone
    end

    def start
      super
      start_reader
    end

    def connection_complete
      super
      info "Connection to site #{@site_ids.first} established"
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

    def version_accepted message, rsmp_version
      log "Received Version message for sites [#{@site_ids.join(',')}] using RSMP #{rsmp_version}", message
      start_timer
      acknowledge message
      send_version rsmp_version
      @version_determined = true

      site_id = @site_ids.first
      if @settings['sites']
        @site_settings = @settings['sites'][site_id]
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
          component = build_component c_id
          info "Adding component #{c_id} to site #{site_id}", message
        else
          reason = "component #{c_id} not found"
          dont_acknowledge message, "Ignoring #{message.type}:", reason
          return
        end
      end

      component.set_aggregated_status_bools se
      log "Received #{message.type} status for component #{c_id} [#{component.aggregated_status.join(', ')}]", message
      acknowledge message
    end

    def aggrated_status_changed component
      @supervisor.aggregated_status_changed self, component
    end

    def process_alarm message
      alarm_code = message.attribute("aCId")
      asp = message.attribute("aSp")
      status = ["ack","aS","sS"].map { |key| message.attribute(key) }.join(',')
      log "Received #{message.type}, #{alarm_code} #{asp} [#{status}]", message
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

    def check_site_id site_id
      @site_settings = @supervisor.check_site_id site_id
    end

    def request_status component, status_list, timeout=nil
      raise NotReady unless @state == :ready
      message = RSMP::StatusRequest.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => status_list
      })
      send message
      return message, wait_for_status_response(component: component, timeout: timeout)
    end

    def process_status_response message
      log "Received #{message.type}", message
      acknowledge message
    end

    def wait_for_status_response options
      raise ArgumentError unless options[:component]
      item = @archive.capture(@task, options.merge(type: "StatusResponse", with_message: true, num: 1)) do |item|
        # check component
      end
      item[:message] if item
    end

    def subscribe_to_status component, status_list
      raise NotReady unless @state == :ready
      message = RSMP::StatusSubscribe.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => status_list
      })
      send message
      message
    end

    def unsubscribe_to_status component, status_list
      raise NotReady unless @state == :ready
      message = RSMP::StatusUnsubscribe.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => status_list
      })
      send message
      message
    end

    def process_status_update message
      log "Received #{message.type}", message
      acknowledge message
    end

    def wait_for_status_update options={}
      raise ArgumentError unless options[:component]
      item = @archive.capture(options.merge(type: "StatusUpdate", with_message: true, num: 1)) do |item|
        # check component
      end
      item[:message] if item
    end

    def send_command component, args
      raise NotReady unless @state == :ready
      message = RSMP::CommandRequest.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "arg" => args
      })
      send message
      message
    end

    def process_command_response message
      log "Received #{message.type}", message
      acknowledge message
    end

    def wait_for_command_response options
      raise ArgumentError unless options[:component]
      item = @archive.capture(@task,options.merge(num: 1, type: "CommandResponse", with_message: true)) do |item|
         # check component
      end
      item[:message] if item
    end

    def set_watchdog_interval interval
      @settings["watchdog_interval"] = interval
    end

  end
end