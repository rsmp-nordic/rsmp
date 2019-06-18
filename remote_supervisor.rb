# handles connection to a single remote supervisor

require_relative 'remote'

module RSMP  
  class RemoteSupervisor < Remote

    attr_reader :supervisor_id, :site

    def initialize options
      super options
      @site = options[:site]
      @settings = @site.site_settings
    end

    def start
      super
      connect
      start_reader
      send_version @settings["rsmp_versions"].first
    rescue Errno::ECONNREFUSED
      error "No connection to supervisor at #{@settings["supervisor_ip"]}:#{@settings["port"]}"
    end

    def connect
      return if @socket
      @socket = TCPSocket.open @settings["supervisor_ip"], @settings["port"]  # connect to supervisor
    end

    def connection_complete
      super
      info "Connection to supervisor established"
      start_watchdog
    end

    def version_accepted message, rsmp_version
      log "Received Version message for sites [#{@site_ids.join(',')}] using RSMP #{rsmp_version}", message
      start_timeout
      acknowledge message
      connection_complete
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

  end
end