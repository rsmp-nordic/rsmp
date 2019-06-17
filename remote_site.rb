# handles connection to a single remote client

require_relative 'remote'

module RSMP  
  class RemoteSite < Remote
    attr_reader :supervisor

    def initialize options
      super options
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings

      @aggregated_status = {}
    end

    def run
      start_reader
      @reader.join
      kill_threads
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

    def process_command_request message
      ignore message
    end

    def process_command_response message
      ignore message
    end

    def process_status_request message
      ignore message
    end

    def process_status_response message
      ignore message
    end

    def process_status_subcribe message
      ignore message
    end

    def process_status_update message
      ignore message
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

  end
end