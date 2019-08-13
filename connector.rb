# Base class for conenction to a single site or supervisor

require_relative 'message'
require_relative 'error'
require_relative 'archive'
require_relative 'probe'
require 'timeout'
require 'async/io/protocol/line'

module RSMP  
  class Connector
    attr_reader :site_ids, :state, :archive

    def initialize options
      @settings = options[:settings]
      @logger = options[:logger]
      @task = options[:task]
      @socket = options[:socket]
      @archive = options[:archive]
      @ip = options[:ip]

      clear
    end

    def site_id
      @site_ids.first   #rsmp connection can represent multiple site ids. pick the first
    end

    def run
      start
      @reader.wait if @reader
      stop
    end

    def ready?
      @state == :ready
    end

    def start
      set_state :starting
    end

    def stop
      set_state :stopping
      stop_tasks
      close_socket
      clear
      set_state :stopped
    end

    def clear
      @site_ids = []
      @awaiting_acknowledgement = {}
      @latest_watchdog_received = nil
      @watchdog_started = false
      @version_determined = false
      @ingoing_acknowledged = {}
      @outgoing_acknowledged = {}
      @latest_watchdog_send_at = nil

      @state_mutex = Mutex.new
      @state_condition = ConditionVariable.new

      @acknowledgements = {}
      @acknowledgement_mutex = Mutex.new
      @acknowledgement_condition = ConditionVariable.new
    end

    def close_socket
      if @socket
        @socket.close 
        @socket = nil
      end
    end

    def start_reader  
      @reader = @task.async do
        @stream = Async::IO::Stream.new(@socket)
        # an rsmp message is json terminated with a form-feed
        @protocol = Async::IO::Protocol::Line.new(@stream,"\f")

        begin
          while packet = @protocol.read_line
            begin
              process packet
            rescue Errno::ECONNRESET => e
              #warning "Connection reset by peer"
              break            
            rescue SystemCallError => e # all ERRNO errors
              error "Connector exception: #{e.to_s}"
              break
            rescue StandardError => e
              error ["Connector exception: #{e}",e.backtrace].flatten.join("\n")
              break
            end
          end
        rescue EOFError
          warning "Connection closed"
        end
      end
    end

    def start_watchdog
      debug "Starting watchdog with interval #{@settings["watchdog_interval"]} seconds"
      send_watchdog
      @watchdog_started = true
    end

    def start_timer
      name = "timer"
      interval = @settings["timer_interval"] || 1
      debug "Starting #{name} with interval #{interval} seconds"
      @latest_watchdog_received = RSMP.now_object
      @timer = @task.async do |task|
        loop do
          begin
            now = RSMP.now_object
            break if timer(now) == false
          rescue StandardError => e
            error ["#{name} exception: #{e}",e.backtrace].flatten.join("\n")
          ensure
            task.sleep interval
          end
        end
      end
    end

    def timer now
      p ":timer, now is #{now}"
      check_watchdog_send_time now
      return false if check_ack_timeout now
      return false if check_watchdog_timeout now
    end

    def check_watchdog_send_time now
      return unless @watchdog_started  
      return if @settings["watchdog_interval"] == :never
      if @latest_watchdog_send_at == nil || (now - @latest_watchdog_send_at) >= (@settings["watchdog_interval"]-0.5)
        send_watchdog now
      end
    rescue StandardError => e
      error ["Watchdog error: #{e}",e.backtrace].flatten.join("\n")
    end

    def send_watchdog now=nil
      now = RSMP.now_object unless nil
      message = Watchdog.new( {"wTs" => now})
      send message
      @latest_watchdog_send_at = now
    end

    def check_ack_timeout now
      timeout = @settings["acknowledgement_timeout"]
      # hash cannot be modify during iteration, so clone it
      @awaiting_acknowledgement.clone.each_pair do |m_id, message|
        latest = message.timestamp + timeout
        if now > latest
          error "No acknowledgements for #{message.type} within #{timeout} seconds"
          stop
          return true
        end
      end
      false
    end

    def check_watchdog_timeout now
      timeout = @settings["watchdog_timeout"]
      latest = @latest_watchdog_received + timeout
      if now > latest
        error "No Watchdog within #{timeout} seconds, received at #{@latest_watchdog_received}, now is #{now}, diff #{now-latest}"
        stop
        return true
      end
      false
    end

    def stop_tasks
      @timer.stop
      @reader.stop
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

    def log_not_acknowledged str, message=nil
      log_at_level str, :nack, message
    end

    def info str, message=nil
      log_at_level str, :info, message
    end

    def debug str, message=nil
      log_at_level str, :debug, message
    end

    def log_at_level str, level, message=nil
      item = RSMP::Archive.prepare_item({
        level: level,
        ip: @ip,
        site_id: site_id,
        str: str,
        message: message
      })
      @archive.add item
      @logger.log item
      item
    end

    def send message, reason=nil
      message.generate_json
      message.direction = :out
      expect_acknowledgement message
      @protocol.write_lines message.out
      log_send message, reason
      #message.m_id
    end

    def log_send message, reason=nil
      if reason
        str = "Sent #{message.type} #{reason}"
      else
        str = "Sent #{message.type}"
      end

      if message.type == "MessageNotAck"
        log_not_acknowledged str, message
      else
        log str, message
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
        when StatusUnsubscribe
          process_status_unsubcribe message
        when StatusUpdate
          process_status_update message
        else
          dont_acknowledge message, "Received", "unknown message (#{message.type})"
      end
    rescue InvalidPacket => e
      warning "Received invalid package, must be valid JSON but got #{packet.size} bytes: #{e.message}"
    rescue MalformedMessage => e
      warning "Received malformed message, #{e.message}", Malformed.new(attributes)
      # cannot send NotAcknowledged for a malformed message since we can't read it, just ignore it
    rescue InvalidMessage => e
      dont_acknowledge message, "Received", "invalid #{message.type}, #{e.message}"
    rescue FatalError => e
      dont_acknowledge message, "Rejected #{message.type},", "#{e.message}"
      stop 
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
        raise FatalError.new "RSMP versions [#{message.versions.join(',')}] requested, but we only support [#{@settings["rsmp_versions"].join(',')}]."
      end
    end

    def process_version message
      return extraneous_version message if @version_determined
      check_site_ids message
      rsmp_version = check_rsmp_version message
      set_state :version_determined
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
      check_ingoing_acknowledged original
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

    def set_state state
      @state = state
      @state_condition.broadcast
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

    def send_version rsmp_versions
      versions_hash = [rsmp_versions].flatten.map {|v| {"vers":v} }
      version_response = Version.new({
        "RSMP"=>versions_hash,
        "siteId"=>[{"sId"=>@settings["site_id"]}],
        "SXL"=>"1.1"
      })
      send version_response
    end

    def find_original_for_message message
       @awaiting_acknowledgement[ message.attribute("oMId") ]
    end

    # TODO this might be better handled by a proper event machine using e.g. the EventMachine gem
    def check_outgoing_acknowledged message
      unless @outgoing_acknowledged[message.type]
        @outgoing_acknowledged[message.type] = true
        acknowledged_first_outgoing message
      end
    end

    def check_ingoing_acknowledged message
      unless @ingoing_acknowledged[message.type]
        @ingoing_acknowledged[message.type] = true
        acknowledged_first_ingoing message
      end
    end

    def acknowledged_first_outgoing message
    end

    def acknowledged_first_ingoing message
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

        check_outgoing_acknowledged original

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
          @acknowledgements[ original.m_id ] = message
          @acknowledgement_condition.broadcast
        end
      else
        log_acknowledgement_for_unknown message
      end
    end

    def log_acknowledgement_for_original message, original
      str = "Received #{message.type} for #{original.type} #{message.attribute("oMId")[0..3]}"
      if message.type == 'MessageNotAck'
        log_not_acknowledged str, message
      else
        log str, message
      end
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
      set_state :ready
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
      raise ArgumentError unless original
      start = Time.now
      @acknowledgement_mutex.synchronize do
        loop do
          left = timeout + (start - Time.now)
          message = @acknowledgements.delete(original.m_id)
          return message if message
          return nil if left <= 0
          @acknowledgement_condition.wait(@acknowledgement_mutex,left)
        end
      end
    end

    def wait_for_not_acknowledged original, timeout
      wait_for_acknowledgement original, timeout, type: :not_acknowledged
    end

    def ignore message, reason=nil
      reason = "since we're a #{self.class.name.downcase}" unless reason
      warning "Ignoring #{message.type}, #{reason}", message
      dont_acknowledge message, nil, reason
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

    def process_status_unsubcribe message
      ignore message
    end

    def process_status_update message
      ignore message
    end

  end
end