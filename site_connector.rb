# Handles a site connection to a remote supervisor

require_relative 'connector'

module RSMP  
  class SiteConnector < Connector

    attr_reader :supervisor_id, :site, :aggregated_status_bools

    def initialize options
      super options
      @site = options[:site]
      @site_settings = @site.site_settings
      @ip = options[:ip]
      @port = options[:port]
      @aggregated_status_bools = Array.new(8,false)
    end

    def start
      info "Connecting to superviser at #{@ip}:#{@port}"
      super
      connect
      start_reader
      send_version @site_settings["rsmp_versions"]
    rescue Errno::ECONNREFUSED
      error "No connection to supervisor at #{@ip}:#{@port}"
    end

    def connect
      return if @socket
      @socket = TCPSocket.open @ip, @port  # connect to supervisor
    end

    def connection_complete
      super
      info "Connection to supervisor established"
      start_watchdog
    end

    def acknowledged_first_ingoing message
      # TODO
      # aggregateds status should only be send for later version of rsmp
      # to handle verison differences, we probably need inherited classes
      case message.type
        when "Watchdog"
          send_aggregated_status
      end
    end

    def reconnect_delay
      interval = @site_settings["reconnect_interval"]
      info "Waiting #{interval} seconds before trying to reconnect"
      sleep interval
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

      @aggregated_status_bools = se
      on = []
      keys.each_with_index do |key,index|
        @aggregated_status[key] = se[index]
        on << key if se[index] == true
      end
      on
    end

    def send_aggregated_status
      message = AggregatedStatus.new({
        "aSTS"=>RSMP.now_string,
        "fP"=>nil,
        "fS"=>nil,
        "se"=>@aggregated_status_bools
      })
      send message
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
      log "Received #{message.type}", message
      rvs = []
      message.attributes["arg"].each do |arg|
        rvs << { "cCI": arg["cCI"],
                 "n": arg["n"],
                 "v": arg["v"],
                 "age": "recent" }
      end

      response = CommandResponse.new({
        "cId"=>message.attributes["cId"],
        "cTS"=>RSMP.now_string,
        "rvs"=>rvs
      })
      acknowledge message
      send response
    end

    def process_status_request message
      log "Received #{message.type}", message
      sS = message.attributes["sS"].clone.map do |request|
        request["s"] = rand(100)
        request["q"] = "recent"
        request
      end
      response = StatusResponse.new({
        "cId"=>message.attributes["cId"],
        "sTs"=>RSMP.now_string,
        "sS"=>sS
      })
      acknowledge message
      send response
    end

    def process_status_subcribe message
      log "Received #{message.type}", message
      sS = []
      message.attributes["sS"].each do |arg|
        sS << { "sCI": arg["sCI"],
                 "n": arg["n"],
                 "s": rand(100),
                 "q": "recent" }
      end
      update = StatusUpdate.new({
        "cId"=>message.attributes["cId"],
        "sTs"=>RSMP.now_string,
        "sS"=>sS
      })
      acknowledge message
      send update
    end

    def process_status_unsubcribe message
      acknowledge message
    end

  end
end