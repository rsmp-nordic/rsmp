# Logging class for a connection to a remote site or supervisor.

require 'rubygems'

module RSMP  
  class Proxy
    WRAPPING_DELIMITER = "\f"

    include Logging
    include Wait
    include Notifier
    include Inspect

    attr_reader :state, :archive, :connection_info, :sxl, :task, :collector, :ip, :port

    def initialize options
      initialize_logging options
      setup options
      initialize_distributor
      prepare_collection @settings['collect']
      clear
    end

    def revive options
      setup options
    end

    def setup options
      @settings = options[:settings]
      @task = options[:task]
      @socket = options[:socket]
      @stream = options[:stream]
      @protocol = options[:protocol]
      @ip = options[:ip]
      @port = options[:port]
      @connection_info = options[:info]
      @sxl = nil
      @site_settings = nil  # can't pick until we know the site id
      @state = :stopped
    end

    def inspect
      "#<#{self.class.name}:#{self.object_id}, #{inspector(
        :@acknowledgements,:@settings,:@site_settings
        )}>"
    end

    def clock
      node.clock
    end

    def prepare_collection num
      if num
        @collector = RSMP::Collector.new self, num: num, ingoing: true, outgoing: true
        add_listener @collector
      end
    end

    def collect task, options, &block
      collector = RSMP::Collector.new self, options
      collector.collect task, &block
      collector
    end

    def run
      start
      @reader.wait if @reader
    ensure
      stop unless [:stopped, :stopping].include? @state
    end

    def ready?
      @state == :ready
    end

    def connected?
      @state == :starting || @state == :ready
    end


    def start
      set_state :starting
    end

    def stop
      return if @state == :stopped
      set_state :stopping
      stop_tasks
      notify_error ConnectionError.new("Connection was closed")
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
        @stream ||= Async::IO::Stream.new(@socket)
        @protocol ||= Async::IO::Protocol::Line.new(@stream,WRAPPING_DELIMITER) # rsmp messages are json terminated with a form-feed
        while json = @protocol.read_line
          beginning = Time.now
          message = process_packet json
          duration = Time.now - beginning
          ms = (duration*1000).round(4)
          if duration > 0
            per_second = (1.0 / duration).round
          else
            per_second = Float::INFINITY
          end
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
      rescue StandardError => e
        notify_error e, level: :internal
      end
    end

    def notify_error e, options={}
      node.notify_error e, options
    end

    def start_watchdog
      log "Starting watchdog with interval #{@site_settings['intervals']['watchdog']} seconds", level: :debug
      send_watchdog
      @watchdog_started = true
    end

    def start_timer
      name = "timer"
      interval = @site_settings['intervals']['timer'] || 1
      log "Starting #{name} with interval #{interval} seconds", level: :debug
      @latest_watchdog_received = Clock.now

      @timer = @task.async do |task|
        task.annotate "timer"
        next_time = Time.now.to_f
        loop do
          begin
            now = Clock.now
            timer(now)
          rescue RSMP::Schemer::Error => e
            puts "Timer: Schema error: #{e}"
          rescue EOFError => e
            log "Timer: Connection closed: #{e}", level: :warning
          rescue IOError => e
            log "Timer: IOError", level: :warning
          rescue Errno::ECONNRESET
            log "Timer: Connection reset by peer", level: :warning
          rescue Errno::EPIPE => e
            log "Timer: Broken pipe", level: :warning
          rescue StandardError => e
            notify_error e, level: :internal
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
      return if @site_settings['intervals']['watchdog'] == :never
      if @latest_watchdog_send_at == nil
        send_watchdog now
      else
        # we add half the timer interval to pick the timer
        # event closes to the wanted wathcdog interval
        diff = now - @latest_watchdog_send_at
        if (diff + 0.5*@site_settings['intervals']['timer']) >= (@site_settings['intervals']['watchdog'])
          send_watchdog now
        end
      end
    end

    def send_watchdog now=Clock.now
      message = Watchdog.new( {"wTs" => clock.to_s})
      send_message message
      @latest_watchdog_send_at = now
    end

    def check_ack_timeout now
      timeout = @site_settings['timeouts']['acknowledgement']
      # hash cannot be modify during iteration, so clone it
      @awaiting_acknowledgement.clone.each_pair do |m_id, message|
        latest = message.timestamp + timeout
        if now > latest
          log "No acknowledgements for #{message.type} #{message.m_id_short} within #{timeout} seconds", level: :error
          stop
          notify_error MissingAcknowledgment.new('No ack')
        end
      end
    end

    def check_watchdog_timeout now
      timeout = @site_settings['timeouts']['watchdog']
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

    def get_schemas
      # normally we have an sxl, but during connection, it hasn't been established yet
      # at these times we only validate against the core schema
      # TODO
      # what schema should we use to validate the intial Version and MessageAck messages?
      schemas = { core: '3.1.5' }
      schemas[sxl] = RSMP::Schemer.sanitize_version(sxl_version) if sxl && sxl_version
      schemas
    end

    def send_message message, reason=nil, validate: true
      raise NotReady unless connected?
      raise IOError unless @protocol
      message.direction = :out
      message.generate_json
      message.validate get_schemas unless validate==false
      @protocol.write_lines message.json
      expect_acknowledgement message
      notify message
      log_send message, reason
    rescue EOFError, IOError
      buffer_message message
    rescue SchemaError, RSMP::Schemer::Error => e
      str = "Could not send #{message.type} because schema validation failed: #{e.message}"
      log str, message: message, level: :error
      notify_error e.exception("#{str} #{message.json}")
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

    def should_validate_ingoing_message? message
      return true unless @site_settings
      skip = @site_settings.dig('skip_validation')
      return true unless skip
      klass = message.class.name.split('::').last
      !skip.include?(klass)
    end

    def process_deferred
      node.process_deferred
    end

    def verify_sequence message
      expect_version_message(message) unless @version_determined
    end

    def process_packet json
      attributes = Message.parse_attributes json
      message = Message.build attributes, json
      message.validate(get_schemas) if should_validate_ingoing_message?(message)
      verify_sequence message
      deferred_notify do
        notify message
        process_message message
      end
      process_deferred
      message
    rescue InvalidPacket => e
      str = "Received invalid package, must be valid JSON but got #{json.size} bytes: #{e.message}"
      notify_error e.exception(str)
      log str, level: :warning
      nil
    rescue MalformedMessage => e
      str = "Received malformed message, #{e.message}"
      notify_error e.exception(str)
      log str, message: Malformed.new(attributes), level: :warning
      # cannot send NotAcknowledged for a malformed message since we can't read it, just ignore it
      nil
    rescue SchemaError, RSMP::Schemer::Error => e
      str = "Received invalid #{message.type}, schema errors: #{e.message}"
      log str, message: message, level: :warning
      notify_error e.exception("#{str} #{message.json}"), message: message
      dont_acknowledge message, str
      message
    rescue InvalidMessage => e
      str = "Received", "invalid #{message.type}, #{e.message}"
      notify_error e.exception("#{str} #{message.json}"), message: message
      dont_acknowledge message, str
      message
    rescue FatalError => e
      str = "Rejected #{message.type},"
      notify_error e.exception("#{str} #{message.json}"), message: message
      dont_acknowledge message, str, "#{e.message}"
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

    def rsmp_versions
      return ['3.1.5'] if @site_settings["rsmp_versions"] == 'latest'
      return ['3.1.1','3.1.2','3.1.3','3.1.4','3.1.5'] if @site_settings["rsmp_versions"] == 'all'
      @site_settings["rsmp_versions"]
    end

    def check_rsmp_version message
      versions = rsmp_versions
      # find versions that both we and the client support
      candidates = message.versions & versions
      if candidates.any?
        @rsmp_version = candidates.sort_by { |v| Gem::Version.new(v) }.last  # pick latest version
      else
        raise HandshakeError.new "RSMP versions [#{message.versions.join(',')}] requested, but only [#{versions.join(',')}] supported."
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
    rescue Async::TimeoutError
      raise RSMP::TimeoutError.new "Did not reach state #{state} within #{timeout}s"
    end

    def send_version site_id, rsmp_versions
      if rsmp_versions=='latest'
        versions = ['3.1.5']
      elsif rsmp_versions=='all'
        versions = ['3.1.1','3.1.2','3.1.3','3.1.4','3.1.5']
      else
        versions = [rsmp_versions].flatten
      end
      versions_array = versions.map {|v| {"vers" => v} }

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
      @latest_watchdog_received = Clock.now
      acknowledge message
    end

    def expect_version_message message
      unless message.is_a?(Version) || message.is_a?(MessageAck) || message.is_a?(MessageNotAck)
        raise HandshakeError.new "Version must be received first"
      end
    end

    def connection_complete
      set_state :ready
    end
    
    def version_acknowledged
    end

    def node
      raise 'Must be overridden'
    end

    def author
      node.site_id
    end

    def wait_for_acknowledgement parent_task, options={}, m_id
      collect(parent_task,options.merge({
        type: ['MessageAck','MessageNotAck'],
        num: 1
      })) do |message|
        if message.is_a?(MessageNotAck)
          if message.attribute('oMId') == m_id
            # set result to an exception, but don't raise it.
            # this will be returned by the task and stored as the task result
            # when the parent task call wait() on the task, the exception
            # will be raised in the parent task, and caught by rspec.
            # rspec will then show the error and record the test as failed
            m_id_short = RSMP::Message.shorten_m_id m_id, 8
            result = RSMP::MessageRejected.new "Aggregated status request #{m_id_short} was rejected: #{message.attribute('rea')}"
            next true   # done, no more messages wanted
          end
        elsif message.is_a?(MessageAck)
          next true if message.attribute('oMId') == m_id
        end
        false
      end
    end
  end
end