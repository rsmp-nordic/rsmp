# Handles a supervisor connection to a remote client

require_relative 'connector'

module RSMP  
  class SupervisorConnector < Connector
    attr_reader :supervisor

    def initialize options
      super options
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings

      @aggregated_status = {}

      @command_responses = {}
      @command_response_mutex = Mutex.new
      @command_response_condition = ConditionVariable.new

      @status_responses = {}
      @status_response_mutex = Mutex.new
      @status_response_condition = ConditionVariable.new

      @status_updates = {}
      @status_update_mutex = Mutex.new
      @status_update_condition = ConditionVariable.new
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
      start_timeout
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

    def check_site_ids message
      super
      @supervisor.site_ids_changed
    end

    def check_site_id site_id
      @supervisor.check_site_id site_id
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
      return message, wait_for_status_response(component, timeout)
    end

    def process_status_request message
      dont_acknowledge message, "Ignoring #{message.type},", "not implemented"
    end

    def process_status_response message
      log "Received #{message.type}", message
      acknowledge message
      @status_response_mutex.synchronize do
        c_id = message.attributes["cId"]
        @status_responses[c_id] = message
        @status_response_condition.broadcast
      end
    end

    def wait_for_status_response component_id, timeout
      start = Time.now
      @status_response_mutex.synchronize do
        loop do
          left = timeout + (start - Time.now)
          message = @status_responses.delete(component_id)
          return message if message
          return if left <= 0
          @status_response_condition.wait(@status_response_mutex,left)
        end
      end
    end

    def subscribe_to_status component, status_list, timeout
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

    def process_status_update message
      log "Received #{message.type}", message
      acknowledge message
      @status_update_mutex.synchronize do
        c_id = message.attributes["cId"]
        @status_updates[c_id] = message
        @status_update_condition.broadcast
      end
    end

    def wait_for_status_update component_id, timeout
      raise ArgumentError unless component_id
      raise ArgumentError unless timeout      
      start = Time.now
      @status_update_mutex.synchronize do
        loop do
          left = timeout + (start - Time.now)
          message = @status_updates.delete(component_id)
          return message if message
          return if left <= 0
          @status_update_condition.wait(@status_update_mutex,left)
        end
      end
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
      @command_response_mutex.synchronize do
        c_id = message.attributes["cId"]
        @command_responses[c_id] = message
        @command_response_condition.broadcast
      end
    end

    def wait_for_command_response component_id, timeout
      start = Time.now
      @command_response_mutex.synchronize do
        loop do
          left = timeout + (start - Time.now)
          message = @command_responses.delete(component_id)
          return message if message
          return if left <= 0
          @command_response_condition.wait(@command_response_mutex,left)
        end
      end
    end

  end
end