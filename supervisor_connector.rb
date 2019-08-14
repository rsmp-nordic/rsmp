# Handles a supervisor connection to a remote client

require_relative 'connector'

module RSMP  
  class SupervisorConnector < Connector
    attr_reader :supervisor

    def initialize options
      super options
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone

      @aggregated_status = {}
      @site_settings = nil
    end

    def start
      super
      start_reader
    end

    def connection_complete
      super
      info "Connection to site established"
    end

    def version_accepted message, rsmp_version
      log "Received Version message for sites [#{@site_ids.join(',')}] using RSMP #{rsmp_version}", message
      start_timer
      acknowledge message
      send_version rsmp_version
      @version_determined = true
    end

    def validate_aggregated_status  message, se
      unless se && se.is_a?(Array) && se.size == 8
        reason = 
        dont_acknowledge message, "Received", "invalid AggregatedStatus, 'se' must be an Array of size 8"
        raise InvalidMessage
      end
    end

    def set_aggregated_status se
      keys = [ :local_control,
               :communication_distruption,
               :high_priority_alarm,
               :medium_priority_alarm,
               :low_priority_alarm,
               :normal,
               :rest,
               :not_connected ]

      on = []
      keys.each_with_index do |key,index|
        @aggregated_status[key] = se[index]
        on << key if se[index] == true
      end
      on
    end

    def process_aggregated_status message
      se = message.attribute("se")
      validate_aggregated_status(message,se) == false
      on = set_aggregated_status se
      log "Received #{message.type} status [#{on.join(', ')}]", message
      acknowledge message
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

    def process_status_request message
      dont_acknowledge message, "Ignoring #{message.type},", "not implemented"
    end

    def process_status_response message
      log "Received #{message.type}", message
      acknowledge message
    end

    def wait_for_status_response options
      raise ArgumentError unless options[:component]
      item = @archive.capture(options.merge(type: "StatusResponse", with_message: true, num: 1)) do |item|
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
    end

    def process_command_response message
      log "Received #{message.type}", message
      acknowledge message
    end

    def wait_for_command_response options
      raise ArgumentError unless options[:component]
      item = @archive.capture(options.merge(num: 1, type: "CommandResponse", with_message: true)) do |item|
         # check component
      end
      item[:message] if item
    end

    def set_watchdog_interval interval
      @settings["watchdog_interval"] = interval
    end

  end
end