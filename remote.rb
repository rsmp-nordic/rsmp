# Base class for conenction to a single site or supervisor

require_relative 'message'
require_relative 'error'
require 'timeout'

module RSMP  
  class Remote
    attr_reader :site_ids

    def initialize options
      @settings = options[:settings]
      @logger = options[:logger]
      @info = options[:info]
      @socket = options[:socket]
      @site_ids = []
      @state = :starting
      @awaiting_acknowledgement = {}
      @latest_watchdog_received = nil
      @watchdog_started = false
      @version_determined = false
      @threads = []

      @state_mutex = Mutex.new
      @state_condition = ConditionVariable.new

      @acknowledgements = {}
      @not_acknowledgements = {}
      @acknowledgement_mutex = Mutex.new
      @acknowledgement_condition = ConditionVariable.new
    end

    def site_id
      @site_ids.first   #rsmp connection can represent multiple site ids. pick the first
    end

    def close
      @socket.close
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
      @reader = Thread.new(@socket) do |socket|
        Thread.current[:name] = "reader"
        # an rsmp message is json terminated with a form-feed
        while packet = socket.gets(RSMP::WRAPPING_DELIMITER)
          if packet
            packet.chomp!(RSMP::WRAPPING_DELIMITER)
            begin
              process packet
            rescue StandardError => e
              error ["Uncaught exception: #{e}",e.backtrace].flatten.join("\n")
            end
          end
        end
        warning "Site closed connection"
      end
    end

    def start_watchdog
      name = "watchdog"
      interval = @settings["watchdog_interval"]
      info "Starting #{name} with interval #{interval} seconds"
      @threads << Thread.new(@socket) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            message = Watchdog.new( {"wTs" => RSMP.now_string})
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
      @latest_watchdog_received = RSMP.now_object
      @threads << Thread.new(@socket) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            now = RSMP.now_object
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
      timeout = @settings["acknowledgement_timeout"]
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
      timeout = @settings["watchdog_timeout"]
      latest = @latest_watchdog_received + timeout
      if now > latest
        error "No Watchdog within #{timeout} seconds"
        terminate
        return true
      end
      false
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

    def error str, message=nil
      log_at_level str, :error, message
    end

    def warning str, message=nil
      log_at_level str, :warning, message
    end

    def log str, message=nil
      log_at_level str, :log, message
    end

    def info str, message=nil
      log_at_level str, :info, message
    end

    def log_at_level str, level, message=nil
      @logger.log({
        level: level,
        ip: @info[:ip],
        site_id: site_id,
        str: str,
        message: message
      })
    end

    def send message, reason=nil
      message.generate_json
      message.direction = :out
      expect_acknowledgement message
      log_send message, reason
      @socket.print message.out
      message.m_id
    end

    def log_send message, reason=nil
      if reason
        log "Sent #{message.type} #{reason}", message
      else
        log "Sent #{message.type}", message
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
      warning "Received malformed message, #{e.message}", Malformed.new(attributes)
      # cannot send NotAckknowleded for a malformed message since we can't read it, just ignore it
    rescue InvalidMessage => e
      dont_acknowledge message, "Received", "invalid #{message.type}, #{e.message}"
    rescue FatalError => e
      dont_acknowledge message, "Rejected", "#{message.type}, #{e.message}"
      terminate 
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

    def check_rsmp_version message
      # find versions that both we and the client support
      candidates = message.versions & @settings["rsmp_versions"]
      if candidates.any?
        # pick latest version
        version = candidates.sort.last
        return version
      else
        raise FatalError.new "RSMP versions [#{message.versions.join(',')}] requested, but we only support [#{@server.rsmp_versions.join(',')}]."
      end
    end

    def process_version message
      return extraneous_version message if @version_determined
      check_site_ids message
      rsmp_version = check_rsmp_version message
      @phase = :version_determined
      check_sxl_version
      version_accepted message, rsmp_version
    end

    def check_sxl_version
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

    def send_version rsmp_version
      version_response = Version.new({
        "RSMP"=>[{"vers"=>rsmp_version}],
        "siteId"=>[{"sId"=>@settings["site_id"]}],
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
          version_acknowledged
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
      @latest_watchdog_received = RSMP.now_object
      acknowledge message
    end

    def expect_version_message message
      unless message.is_a?(Version) || message.is_a?(MessageAck) || message.is_a?(MessageNotAck)
        raise FatalError.new "Version must be received first"
      end
    end

    def connection_complete
      @state = :ready
    end

    def check_site_ids message
      message.attribute("siteId").map { |item| item["sId"] }.each do |site_id|
        check_site_id site_id
        @site_ids << site_id
      end
    end

    def check_site_id site_id
    end

    def site_id_accetable? site_id
      true
    end

    def add_site_id site_id
      @site_ids << site_id
    end
    
    def version_acknowledged
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

    def ignore message, reason=nil
      reason = "since we're a #{self.class.name.downcase}" unless reason
      warning "Ignoring #{message.type}, #{reason}", message
      dont_acknowledge message
    end

  end
end