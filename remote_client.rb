# handles connection to a single remote client

require_relative 'message'
require_relative 'error'

module RSMP  
  class RemoteClient

    attr_reader :site_ids
    attr_accessor :store_messages
    attr_reader :stored_messages

    def initialize server, client, info
      @server = server
      @client = client
      @info = info
      @awaiting_acknowledgement = {}
      @latest_watchdog_received = nil
      @version_determined = false
      @threads = []
      @site_ids = []
      @aggregated_status = {}
      @stored_messages = []
    end

    def clear_messages_log
      @stored_messages = []
    end

    def run
      start_reader
      @reader.join
      kill_threads
    end

    def terminate
      log "Closing connection"
      @reader.kill
    end

    def kill_threads
      reaper = Thread.new(@threads) do |threads|
        threads.each do |thread|
          log "Stopping #{thread[:name]}"
          thread.kill
        end
      end
      reaper.join
      @threads.clear
    end

    def start_reader    
      @reader = Thread.new(@client) do |socket|
        Thread.current[:name] = "reader"
        # an rsmp message is json terminated with a form-feed
        while packet = socket.gets(Server::WRAPPING_DELIMITER)
          if packet
            packet.chomp!(Server::WRAPPING_DELIMITER)
            begin
              process packet
            rescue StandardError => e
              log "Uncaught exception: #{e}"
              log e.backtrace
            end
          end
        end
        log "Client closed connection"
      end
    end

    def start_watchdog
      name = "watchdog"
      interval = @server.settings["watchdog_interval"]
      log "Starting #{name} with interval #{interval} seconds"
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            message = Watchdog.new( {"wTs" => Server.now_string})
            send message
          rescue StandardError => e
            log "#{name} error: #{e}"
            log e.backtrace
          ensure
            sleep interval
          end
        end
      end
    end

    def start_timeout
      name = "timeout checker"
      interval = 1
      log "Starting #{name} with interval #{interval} seconds"
      @latest_watchdog_received = Server.now_object
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            now = Server.now_object
            break if check_ack_timeout now
            break if check_watchdog_timeout now
          rescue StandardError => e
            log "#{name} error: #{e}"
            log e.backtrace
          ensure
            sleep 1
          end
        end
      end
    end

    def check_ack_timeout now
      timeout = @server.settings["acknowledgement_timeout"]
      # hash cannot be modify during iteration, so clone it
      @awaiting_acknowledgement.clone.each_pair do |mId, data|
        latest = data["timestamp"] + timeout
        if now > latest
          log "No acknowledgements for #{data["type"]} within #{timeout} seconds"
          terminate
          return true
        end
      end
      false
    end

    def check_watchdog_timeout now
      timeout = @server.settings["watchdog_timeout"]
      latest = @latest_watchdog_received + timeout
      if now > latest
        log "No Watchdog within #{timeout} seconds"
        terminate
        return true
      end
      false
    end

    def send message, reason=nil
      message.generate_json
      log_send message, reason
      @client.puts message.out
      store_message message.clone
      expect_acknowledgement message
      message.mId
    end

    def log_send message, reason=nil
      return unless should_log_event? message
      if reason
        log "Sent #{message.type} #{reason}", message
      else
        log "Sent #{message.type}", message
      end
    end

    def log_receive message
      return unless should_log_event? message
    end

    def should_log_event? message
      return false if @server.settings["log_acknowledgements"]==false &&
                (message.type == "MessageAck" || message.type == "MessageNotAck")

      return false if @server.settings["log_watchdogs"]==false && message.type == "Watchdog" 

      true
    end

    def expect_acknowledgement message
      unless message.is_a?(MessageAck) || message.is_a?(MessageNotAck)
        @awaiting_acknowledgement[message.mId] = {
          "type" => message.type,  
          "timestamp" => Server.now_object
        }
      end
    end

    def got_acknowledgement message
      @awaiting_acknowledgement.delete message.attribute("oMId")
    end

    def extraneous_version message
      dont_acknowledge message, "Received", "extraneous Version message"
    end

    def process_version message
      return extraneous_version if @version_determined
      check_site_ids message
      rsmp_version = check_rsmp_version message
      #check_sxl_version
      version_accepted message, rsmp_version
    end

    def check_site_ids message
      message.attribute("siteId").map { |item| item["sId"] }.each do |site_id|
        check_site_id(site_id)
      end
    rescue StandardError => e
      raise FatalError.new e.message
    end

    def check_site_id site_id
      if site_id_accetable? site_id   
        @site_ids << site_id
      else
        raise FatalError.new "Site id #{site_id} rejected"
      end
    end

    def site_id_accetable? site_id
      true
    end

    def check_rsmp_version message
      # find versions that both we and the client support
      candidates = message.versions & @server.rsmp_versions
      if candidates.any?
        # pick latest version
        version = candidates.sort.last
        return version
      else
        raise FatalError.new "RSMP versions [#{message.versions.join(',')}] requested, but we only support [#{@server.rsmp_versions.join(',')}]."
      end
    end

    def version_accepted message, rsmp_version
      log "Received Version message for sites [#{@site_ids.join(',')}] using RSMP #{rsmp_version}"
      start_timeout
      acknowledge message
      send_version rsmp_version
      start_watchdog
      @version_determined = true
    end

    def send_version rsmp_version
      version_response = Version.new({
        "RSMP"=>[{"vers"=>rsmp_version}],
        "siteId"=>[{"sId"=>@server.site_id}],
        "SXL"=>"1.1"
      })
      send version_response
    end

    def process_ack message
      past_item = @awaiting_acknowledgement[ message.attribute("oMId") ]
      
      if @server.settings["log_acknowledgements"]==true
        if past_item
          log "Received #{message.type} for #{past_item["type"]}", message
        else
          log "Received #{message.type}", message
        end
      end
      got_acknowledgement message
    end

    def process_not_ack message
      log "Received #{message.type}", message
      got_acknowledgement message
    end

    def process_watchdog message
      if @server.settings["log_watchdogs"] == true
        log "Received #{message.type}", message
      end
      @latest_watchdog_received = Server.now_object
      acknowledge message
    end

    def expect_version_message message
      unless message.is_a? Version
        raise FatalError.new "Version must be received first"
      end
    end

    def store_message message
      if @server.settings["store_messages"]
        @stored_messages << message
      end
    end

    def process packet
      attributes = Message.parse_attributes packet
      message = Message.build attributes, packet
      expect_version_message(message) unless @version_determined

      store_message message.clone
      case message
        when MessageAck
          process_ack message
        when MessageNotAck
          process_not_ack message
        when Version
          process_version message
        when Watchdog
          process_watchdog message
        when AggregatedStatus
          process_aggregated_status message
        when Alarm
          process_alarm message
        else
          dont_acknowledge message, "Received", "unknown message (#{message.type})"
      end
    rescue InvalidPacket => e
      log "Received invalid package, size=#{packet.size}, content=#{e.message}"
    rescue MalformedMessage => e
      log "Received invalid message, #{e.message}", Malformed.new(attributes)
      # cannot acknowledge a malformed message, just ignore it
    rescue InvalidMessage => e
      dont_acknowledge message, "Received", "invalid #{message.type}, #{e.message}"
    rescue FatalError => e
      dont_acknowledge message, "Received", "invalid #{message.type}, #{e.message}"
      terminate 
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

    def acknowledge message
      ack = MessageAck.build_from(message)
      send ack, "for #{message.type}"
    end

    def dont_acknowledge not_acknowledged_message, prefix=nil, reason=nil
      str = [prefix,reason].join(' ')
      log str, not_acknowledged_message if reason
      message = MessageNotAck.new({
        "oMId" => not_acknowledged_message.mId,
        "rea" => reason || "Unknown reason"
      })
      send message, "for #{not_acknowledged_message.type}"
    end

    def prefix
      site_id = @site_ids.first
      "#{Server.log_prefix(@info[:ip])} #{site_id.to_s.ljust(12)}"
    end

    def log str, message=nil
      if @server.settings["logging"]=="verbose" && message
        @server.log "#{prefix} #{str.ljust(60)} #{message.json.to_s}"
      else
        @server.log "#{prefix} #{str}"
      end
    end
  end
end