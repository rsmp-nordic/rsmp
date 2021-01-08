# Logging class for a connection to a remote site or supervisor.

module RSMP  
  class Proxy
    include Logging
    include Wait
    include Distributor

    attr_reader :state, :archive, :connection_info, :sxl, :task, :collector

    def initialize options
      initialize_logging options
      @settings = options[:settings]
      @task = options[:task]
      @socket = options[:socket]
      @ip = options[:ip]
      @connection_info = options[:info]
      @sxl = nil
      initialize_distributor

      prepare_collection options[:collect]

      clear
    end

    def prepare_collection num
      if num
        @collector = RSMP::Collector.new self, num: num
        add_receiver @collector
      end
    end

    def collect task, options, &block
      probe = RSMP::Collector.new self, options
      probe.collect task, &block
    end

    def run
      start
      @reader.wait if @reader
      stop unless [:stopped, :stopping].include? @state
    end

    def ready?
      @state == :ready
    end

    def start
      set_state :starting
    end

    def stop
      return if @state == :stopped
      set_state :stopping
      stop_tasks
    ensure
      close_socket
      clear
      set_state :stopped
    end

    def clear
      @awaiting_acknowledgement = {}
      @latest_watchdog_received = nil
      @watchdog_started = false
      @version_determined = false
      @ingoing_acknowledged = {}
      @outgoing_acknowledged = {}
      @latest_watchdog_send_at = nil

      @state_condition = Async::Notification.new
      @acknowledgements = {}
      @acknowledgement_condition = Async::Notification.new
    end

    def close_socket
      if @stream
        @stream.close
        @stream = nil
      end

      if @socket
        @socket.close
        @socket = nil
      end
    end

    def start_reader  
      @reader = @task.async do |task|
        task.annotate "reader"
        @stream = Async::IO::Stream.new(@socket)
        @protocol = Async::IO::Protocol::Line.new(@stream,RSMP::WRAPPING_DELIMITER) # rsmp messages are json terminated with a form-feed

        while json = @protocol.read_line
          beginning = Time.now
          message = process_packet json
          duration = Time.now - beginning
          ms = (duration*1000).round(4)
          per_second = (1.0 / duration).round
          if message
            type = message.type
            m_id = Logger.shorten_message_id(message.m_id)
          else
            type = 'Unknown'
            m_id = nil
          end
          str = [type,m_id,"processed in #{ms}ms, #{per_second}req/s"].compact.join(' ')
          log str, level: :statistics
        end
      rescue Async::Wrapper::Cancelled
        # ignore        
      rescue EOFError
        log "Connection closed", level: :warning
      rescue IOError => e
        log "IOError: #{e}", level: :warning
      rescue Errno::ECONNRESET
        log "Connection reset by peer", level: :warning
      rescue Errno::EPIPE
        log "Broken pipe", level: :warning
      rescue SystemCallError => e # all ERRNO errors
        log "Proxy exception: #{e.to_s}", level: :error
      rescue StandardError => e
        log ["Proxy exception: #{e.inspect}",e.backtrace].flatten.join("\n"), level: :error
      end
    end

    def start_watchdog
      log "Starting watchdog with interval #{@settings["watchdog_interval"]} seconds", level: :debug
      send_watchdog
      @watchdog_started = true
    end

    def start_timer
      name = "timer"
      interval = @settings["timer_interval"] || 1
      log "Starting #{name} with interval #{interval} seconds", level: :debug
      @latest_watchdog_received = RSMP.now_object

      @timer = @task.async do |task|
        task.annotate "timer"
        next_time = Time.now.to_f
        loop do
          begin
            now = RSMP.now_object
            timer(now)
          rescue EOFError => e
            log "Timer: Connection closed: #{e}", level: :warning
          rescue IOError => e
            log "Timer: IOError", level: :warning
          rescue Errno::ECONNRESET
            log "Timer: Connection reset by peer", level: :warning
          rescue Errno::EPIPE => e
            log "Timer: Broken pipe", level: :warning
          rescue StandardError => e
            log "Error: #{e}", level: :debug
          #rescue StandardError => e
          #  log ["Timer error: #{e}",e.backtrace].flatten.join("\n"), level: :error
          end
        ensure
          next_time += interval
          duration = next_time - Time.now.to_f
          task.sleep duration
        end
      end
    end

    def timer now
      watchdog_send_timer now
      check_ack_timeout now
      check_watchdog_timeout now
    end

    def watchdog_send_timer now
      return unless @watchdog_started  
      return if @settings["watchdog_interval"] == :never
      
      if @latest_watchdog_send_at == nil
        send_watchdog now
      else
        # we add half the timer interval to pick the timer
        # event closes to the wanted wathcdog interval
        diff = now - @latest_watchdog_send_at
        if (diff + 0.5*@settings["timer_interval"]) >= (@settings["watchdog_interval"])
          send_watchdog now
        end
      end
    end

    def send_watchdog now=nil
      now = RSMP.now_object unless nil
      message = Watchdog.new( {"wTs" => RSMP.now_object_to_string(now)})
      send_message message
      @latest_watchdog_send_at = now
    end

    def check_ack_timeout now
      timeout = @settings["acknowledgement_timeout"]
      # hash cannot be modify during iteration, so clone it
      @awaiting_acknowledgement.clone.each_pair do |m_id, message|
        latest = message.timestamp + timeout
        if now > latest
          log "No acknowledgements for #{message.type} #{message.m_id_short} within #{timeout} seconds", level: :error
          stop
        end
      end
    end

    def check_watchdog_timeout now
      timeout = @settings["watchdog_timeout"]
      latest = @latest_watchdog_received + timeout
      left = latest - now
      if left < 0
        log "No Watchdog within #{timeout} seconds", level: :error
        stop
      end
    end

    def stop_tasks
      @timer.stop if @timer
      @reader.stop if @reader
    end

    def log str, options={}
      super str, options.merge(ip: @ip, port: @port, site_id: @site_id)
    end

    def send_message message, reason=nil
      raise IOError unless @protocol
      message.generate_json
      message.validate sxl
      message.direction = :out
      expect_acknowledgement message
      @protocol.write_lines message.json
      log_send message, reason
    rescue EOFError, IOError
      buffer_message message
    rescue SchemaError => e
      log "Error sending #{message.type}, schema validation failed: #{e.message}", message: message, level: :error
    end

    def buffer_message message
      # TODO
      #log "Cannot send #{message.type} because the connection is closed.", message: message, level: :error
    end

    def log_send message, reason=nil
      if reason
        str = "Sent #{message.type} #{reason}"
      else
        str = "Sent #{message.type}"
      end

      if message.type == "MessageNotAck"
        log str, message: message, level: :warning
      else
        log str, message: message, level: :log
      end
    end

    def process_packet json
      attributes = Message.parse_attributes json
      message = Message.build attributes, json
      message.validate sxl
      expect_version_message(message) unless @version_determined
      process_message message
      process_deferred
      distribute( message: message )
      message
    rescue InvalidPacket => e
      log "Received invalid package, must be valid JSON but got #{json.size} bytes: #{e.message}", level: :warning
      nil
    rescue MalformedMessage => e
      log "Received malformed message, #{e.message}", message: Malformed.new(attributes), level: :warning
      # cannot send NotAcknowledged for a malformed message since we can't read it, just ignore it
      nil
    rescue SchemaError => e
      dont_acknowledge message, "Received", "invalid #{message.type}, schema errors: #{e.message}"
      message
    rescue InvalidMessage => e
      dont_acknowledge message, "Received", "invalid #{message.type}, #{e.message}"
      message
    rescue FatalError => e
      dont_acknowledge message, "Rejected #{message.type},", "#{e.message}"
      stop
      message
    end

    def process_message message
      case message
        when MessageAck
          process_ack message
        when MessageNotAck
          process_not_ack message
        when Version
          process_version message
        when Watchdog
          process_watchdog message
        else
          dont_acknowledge message, "Received", "unknown message (#{message.type})"
      end
    end

    def will_not_handle message
      reason = "since we're a #{self.class.name.downcase}" unless reason
      log "Ignoring #{message.type}, #{reason}", message: message, level: :warning
      dont_acknowledge message, nil, reason
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
        @rsmp_version = candidates.sort.last  # pick latest version
      else
        raise FatalError.new "RSMP versions [#{message.versions.join(',')}] requested, but only [#{@settings["rsmp_versions"].join(',')}] supported."
      end
    end

    def process_version message
    end

    def acknowledge original
      raise InvalidArgument unless original
      ack = MessageAck.build_from(original)
      ack.original = original.clone
      send_message ack, "for #{ack.original.type} #{original.m_id_short}"
      check_ingoing_acknowledged original
    end

    def dont_acknowledge original, prefix=nil, reason=nil
      raise InvalidArgument unless original
      str = [prefix,reason].join(' ')
      log str, message: original, level: :warning if reason
      message = MessageNotAck.new({
        "oMId" => original.m_id,
        "rea" => reason || "Unknown reason"
      })
      message.original = original.clone
      send_message message, "for #{original.type} #{original.m_id_short}"
    end

    def set_state state
      @state = state
      @state_condition.signal @state
    end

    def wait_for_state state, timeout
      states = [state].flatten
      return if states.include?(@state)
      wait_for(@state_condition,timeout) do
        states.include?(@state)
      end
      @state
    end

    def send_version site_id, rsmp_versions
      versions_array = [rsmp_versions].flatten.map {|v| {"vers" => v} }
      site_id_array = [site_id].flatten.map {|id| {"sId" => id} }

      version_response = Version.new({
        "RSMP"=>versions_array,
        "siteId"=>site_id_array,
        "SXL"=>sxl_version
      })
      send_message version_response
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

        @acknowledgements[ original.m_id ] = message
        @acknowledgement_condition.signal message
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
        @acknowledgements[ original.m_id ] = message
        @acknowledgement_condition.signal message
      else
        log_acknowledgement_for_unknown message
      end
    end

    def log_acknowledgement_for_original message, original
      str = "Received #{message.type} for #{original.type} #{message.attribute("oMId")[0..3]}"
      if message.type == 'MessageNotAck'
        reason = message.attributes["rea"]
        str = "#{str}: #{reason}" if reason
        log str, message: message, level: :warning
      else
        log str, message: message, level: :log
      end
    end

    def log_acknowledgement_for_unknown message
      log "Received #{message.type} for unknown message #{message.attribute("oMId")[0..3]}", message: message, level: :warning
    end

    def process_watchdog message
      log "Received #{message.type}", message: message, level: :log
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
    
    def version_acknowledged
    end

    def wait_for_acknowledgement original, timeout
      raise ArgumentError unless original
      wait_for(@acknowledgement_condition,timeout) do |message|
        if message.is_a?(MessageNotAck) && message.attributes["oMId"] == original.m_id
          raise RSMP::MessageRejected.new(message.attributes['rea'])
        end
        message.is_a?(MessageAck) && message.attributes["oMId"] == original.m_id
      end
    rescue Async::TimeoutError
      raise RSMP::TimeoutError.new("Acknowledgement for #{original.type} #{original.m_id} not received within #{timeout}s")
    end

    def node
      raise 'Must be overridden'
    end

    def author
      node.site_id
    end
  end
end