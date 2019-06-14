# handles connection to a single remote client

require_relative 'message'
require_relative 'error'
require 'timeout'

module RSMP  
  class RemoteClient

    attr_reader :site_ids, :server

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
      @watchdog_started = false
      @state = :starting
      @state_mutex = Mutex.new
      @state_condition = ConditionVariable.new

      @command_responses = {}
      @command_response_mutex = Mutex.new
      @command_response_condition = ConditionVariable.new

      @status_responses = {}
      @status_response_mutex = Mutex.new
      @status_response_condition = ConditionVariable.new

      @status_updates = {}
      @status_update_mutex = Mutex.new
      @status_update_condition = ConditionVariable.new

      @acknowledgements = {}
      @not_acknowledgements = {}
      @acknowledgement_mutex = Mutex.new
      @acknowledgement_condition = ConditionVariable.new
    end

    def run
      start_reader
      @reader.join
      kill_threads
    end

    def close
      @client.close
    end

    def terminate
      @state = :stopping
      info "Closing connection"
      @reader.kill
    end

    def kill_threads
      reaper = Thread.new(@threads) do |threads|
        threads.each do |thread|
          info "Stopping #{thread[:name]}"
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
              error ["Uncaught exception: #{e}",e.backtrace].flatten.join("\n")
            end
          end
        end
        warning "Client closed connection"
      end
    end

    def start_watchdog
      name = "watchdog"
      interval = @server.supervisor_settings["watchdog_interval"]
      info "Starting #{name} with interval #{interval} seconds"
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            message = Watchdog.new( {"wTs" => Server.now_string})
            send message
          rescue StandardError => e
            error ["#{name} error: #{e}",e.backtrace].flatten.join("\n")
          end
          sleep interval
        end
      end
      @watchdog_started = true
    end

    def start_timeout
      name = "timeout checker"
      interval = 1
      info "Starting #{name} with interval #{interval} seconds"
      @latest_watchdog_received = Server.now_object
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            now = Server.now_object
            break if check_ack_timeout now
            break if check_watchdog_timeout now
          rescue StandardError => e
            error ["#{name} error: #{e}",e.backtrace].flatten.join("\n")
          ensure
            sleep 1
          end
        end
      end
    end

    def check_ack_timeout now
      timeout = @server.supervisor_settings["acknowledgement_timeout"]
      # hash cannot be modify during iteration, so clone it
      @awaiting_acknowledgement.clone.each_pair do |m_id, message|
        latest = message.timestamp + timeout
        if now > latest
          error "No acknowledgements for #{message.type} within #{timeout} seconds"
          terminate
          return true
        end
      end
      false
    end

    def check_watchdog_timeout now
      timeout = @server.supervisor_settings["watchdog_timeout"]
      latest = @latest_watchdog_received + timeout
      if now > latest
        error "No Watchdog within #{timeout} seconds"
        terminate
        return true
      end
      false
    end

    def send message, reason=nil
      message.generate_json
      message.direction = :out
      log_send message, reason
      @client.puts message.out
      expect_acknowledgement message
      message.m_id
    end

    def log_send message, reason=nil
      if reason
        log "Sent #{message.type} #{reason}", message
      else
        log "Sent #{message.type}", message
      end
    end

    def expect_acknowledgement message
      unless message.is_a?(MessageAck) || message.is_a?(MessageNotAck)
        @awaiting_acknowledgement[message.m_id] = message
      end
    end

    def dont_expect_acknowledgement message
      @awaiting_acknowledgement.delete message.attribute("oMId")
    end

    def extraneous_version message
      dont_acknowledge message, "Received", "extraneous Version message"
    end

    def process_version message
      return extraneous_version if @version_determined
      check_site_ids message
      rsmp_version = check_rsmp_version message
      @phase = :version_determined
      check_sxl_version
      version_accepted message, rsmp_version
    end

    def check_sxl_version
    end

    def check_site_ids message
      message.attribute("siteId").map { |item| item["sId"] }.each do |site_id|
        check_site_id(site_id)
      end
      @phase = :site_id_accepted
      @server.site_ids_changed
    rescue StandardError => e
      raise FatalError.new e.message
    end

    def check_site_id site_id
      if site_id_accetable? site_id
        add_site_id site_id
      else
        raise FatalError.new "Site id #{site_id} rejected"
      end
    end

    def add_site_id site_id
      @site_ids << site_id
    end

    def connection_complete
      @state = :ready
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
      log "Received Version message for sites [#{@site_ids.join(',')}] using RSMP #{rsmp_version}", message
      start_timeout
      acknowledge message
      send_version rsmp_version
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

    def find_original_for_message message
       @awaiting_acknowledgement[ message.attribute("oMId") ]
    end

    def process_ack message
      original = find_original_for_message message
      if original
        dont_expect_acknowledgement message
        message.original = original
        log_acknowledgement_for_original message, original
        if original.type == "Version"
          connection_complete
        end
        @acknowledgement_mutex.synchronize do
          @acknowledgements[ original.m_id ] = message
          @acknowledgement_condition.broadcast
        end
      else
        log_acknowledgement_for_unknown message
      end
    end

    def process_not_ack message
      original = find_original_for_message message
      if original
        dont_expect_acknowledgement message
        message.original = original
        log_acknowledgement_for_original message, original
        @acknowledgement_mutex.synchronize do
          @not_acknowledgements[ original.m_id ] = message
          @acknowledgement_condition.broadcast
        end
      else
        log_acknowledgement_for_unknown message
      end
    end

    def log_acknowledgement_for_original message, original
      log "Received #{message.type} for #{original.type} #{message.attribute("oMId")[0..3]}", message
    end

    def log_acknowledgement_for_unknown message
      warning "Received #{message.type} for unknown message #{message.attribute("oMId")[0..3]}", message
    end

    def process_watchdog message
      log "Received #{message.type}", message
      @latest_watchdog_received = Server.now_object
      acknowledge message
      if @watchdog_started == false
        start_watchdog
      end
    end

    def expect_version_message message
      unless message.is_a? Version
        raise FatalError.new "Version must be received first"
      end
    end

    def process packet
      attributes = Message.parse_attributes packet
      message = Message.build attributes, packet
      expect_version_message(message) unless @version_determined
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
        when CommandRequest
          process_command_request message
        when CommandResponse
          process_command_response message
        when StatusRequest
          process_status_request message
        when StatusResponse
          process_status_response message
        when StatusSubscribe
          process_status_subcribe message
        when StatusUpdate
          process_status_update message
        else
          dont_acknowledge message, "Received", "unknown message (#{message.type})"
      end
    rescue InvalidPacket => e
      warning "Received invalid package, must be valid JSON but got #{packet.size} bytes: #{e.message}"
    rescue MalformedMessage => e
      warning "Received invalid message, #{e.message}", Malformed.new(attributes)
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

    def acknowledge original
      raise InvalidArgument unless original
      ack = MessageAck.build_from(original)
      ack.original = original.clone
      send ack, "for #{ack.original.type} #{original.m_id[0..3]}"
    end

    def dont_acknowledge original, prefix=nil, reason=nil
      raise InvalidArgument unless original
      str = [prefix,reason].join(' ')
      warning str, original if reason
      message = MessageNotAck.new({
        "oMId" => original.m_id,
        "rea" => reason || "Unknown reason"
      })
      message.original = original.clone
     send message, "for #{original.type}"
    end

    def prefix
      site_id = @site_ids.first
      "#{Server.log_prefix(@info[:ip])} #{site_id.to_s.ljust(12)}"
    end

    def error str, message=nil
      output str, :error, message
    end

    def warning str, message=nil
      output str, :warning, message
    end

    def log str, message=nil
      output str, :log, message
    end

    def info str, message=nil
      output str, :info, message
    end

    def output str, level, message=nil
      @server.log({
        level: level,
        ip: @info[:ip],
        site_id: @site_ids.first,
        str: str,
        message: message
      })
    end

    def send_command component, args, timeout=nil
      raise NotReady unless @state == :ready
      message = RSMP::CommandRequest.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "arg" => args
      })
      send message
      return message, wait_for_command_response(component, timeout)
    end

    def state= state
      @state_mutex.synchronize do
        @state_condition.broadcast
      end
    end

    def wait_for_state state, timeout
      start = Time.now
      @state_mutex.synchronize do
        loop do
          left = timeout + (start - Time.now)
          return true if @state == state
          return @state if left <= 0
          @state_condition.wait(@state_mutex,left)
        end
      end
    end

    def process_command_request message
      ignore message
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

    def wait_for_acknowledgement original, timeout, options={}
      raise InvalidArgument unless original
      start = Time.now
      @acknowledgement_mutex.synchronize do
        loop do
          left = timeout + (start - Time.now)
          unless options[:not_acknowledged]
            message = @acknowledgements.delete(original.m_id)
          else
            message = @not_acknowledgements.delete(original.m_id)
          end  
          return message if message
          return if left <= 0
          @acknowledgement_condition.wait(@acknowledgement_mutex,left)
        end
      end
    end

    def wait_for_not_acknowledged original, timeout
      wait_for_acknowledgement original, timeout, not_acknowledged: true
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
      ignore message
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

    def ignore message
      warning "Ignoring #{message.type}, since we're a supervisor", message
      dont_acknowledge message
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
      return message, wait_for_status_update(component, timeout)
    end

    def process_status_subscribe message
      ignore message
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
  end
end