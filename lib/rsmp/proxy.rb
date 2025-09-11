# A connection to a remote site or supervisor.
# Uses the Task module to handle asyncronous work, but adds
# the concept of a connection that can be connected or disconnected.

require 'rubygems'

module RSMP
  class Proxy
    WRAPPING_DELIMITER = "\f"

    include Logging
    include Distributor
    include Inspect
    include Task

    attr_reader :state, :archive, :connection_info, :sxl, :collector, :ip, :port, :node, :core_version
    def initialize options
      @node = options[:node]
      initialize_logging options
      initialize_distributor
      initialize_task
      setup options
      clear
      @state = :disconnected
      @state_condition = Async::Notification.new
    end


    def now
      node.now
    end

    def disconnect
    end


    # wait for the reader task to complete,
    # which is not expected to happen before the connection is closed
    def wait_for_reader
      @reader.wait if @reader
    end

    # close connection, but keep our main task running so we can reconnect
    def close
      log "Closing connection", level: :warning
      close_stream
      close_socket
      stop_reader
      set_state :disconnected
      distribute_error DisconnectError.new("Connection was closed")

      # stop timer
      # as we're running inside the timer, code after stop_timer() will not be called,
      # unless it's in the ensure block
      stop_timer
    end

    def stop_subtasks
      stop_timer
      stop_reader
      clear
      super
    end

    def stop_timer
      @timer.stop if @timer
    ensure
      @timer = nil
    end

    def stop_reader
      @reader.stop if @reader
    ensure
      @reader = nil
    end

    def close_stream
      @stream.close if @stream
    ensure
      @stream = nil
    end

    def close_socket
      @socket.close if @socket
    ensure
      @socket = nil
    end

    def stop_task
      close
      super
    end

    # change our state
    def set_state state
      return if state == @state
      @state = state
      state_changed
    end

    # the state changed
    # override to to things like notifications
    def state_changed
      @state_condition.signal @state
    end

    # revive after a reconnect
    def revive options
      setup options
    end

    def setup options
      @settings = options[:settings]
      @socket = options[:socket]
      @stream = options[:stream]
      @protocol = options[:protocol]
      @ip = options[:ip]
      @port = options[:port]
      @connection_info = options[:info]
      @sxl = nil
      @site_settings = nil  # can't pick until we know the site id
      if options[:collect]
        @collector = RSMP::Collector.new self, options[:collect]
        @collector.start
      end
    end

    def inspect
      "#<#{self.class.name}:#{self.object_id}, #{inspector(
        :@acknowledgements,:@settings,:@site_settings
        )}>"
    end

    def clock
      @node.clock
    end

    def ready?
      @state == :ready
    end

    def connected?
      @state == :connected || @state == :ready
    end

    def disconnected?
      @state == :disconnected
    end

    def clear
      @awaiting_acknowledgement = {}
      @latest_watchdog_received = nil
      @watchdog_started = false
      @version_determined = false
      @ingoing_acknowledged = {}
      @outgoing_acknowledged = {}
      @latest_watchdog_send_at = nil

      @acknowledgements = {}
      @acknowledgement_condition = Async::Notification.new
    end

    # run an async task that reads from @socket
    def start_reader
      @reader = @task.async do |task|
        task.annotate "reader"
        run_reader
      end
    end

    def run_reader
      @stream ||= IO::Stream::Buffered.new(@socket)
      @protocol ||= RSMP::Protocol.new(@stream) # rsmp messages are json terminated with a form-feed
      loop do
        read_line
      end
    rescue Restart
      log "Closing connection", level: :warning
      raise
    rescue EOFError, Async::Stop
      log "Connection closed", level: :warning
    rescue IOError => e
      log "IOError: #{e}", level: :warning
    rescue Errno::ECONNRESET
      log "Connection reset by peer", level: :warning
    rescue Errno::EPIPE
      log "Broken pipe", level: :warning
    rescue StandardError => e
      distribute_error e, level: :internal
    end

    def read_line
      json = @protocol.read_line
      raise EOFError, "Connection closed - no more data to read" unless json
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

    def receive_error e, options={}
      @node.receive_error e, options
    end

    def start_watchdog
      log "Starting watchdog with interval #{@site_settings['intervals']['watchdog']} seconds", level: :debug
      @watchdog_started = true
    end

    def stop_watchdog
      log "Stopping watchdog", level: :debug
      @watchdog_started = false
    end

    def with_watchdog_disabled
      was = @watchdog_started
      stop_watchdog if was
      yield
    ensure
      start_watchdog if was
    end


    def start_timer
      return if @timer
      name = "timer"
      interval = @site_settings['intervals']['timer'] || 1
      log "Starting #{name} with interval #{interval} seconds", level: :debug
      @latest_watchdog_received = Clock.now
      @timer = @task.async do |task|
        task.annotate "timer"
        run_timer task, interval
      end
    end

    def run_timer task, interval
      next_time = Time.now.to_f
      loop do
        begin
          now = Clock.now
          timer(now)
        rescue RSMP::Schema::Error => e
          log "Timer: Schema error: #{e}", level: :warning
        rescue EOFError => e
          log "Timer: Connection closed: #{e}", level: :warning
        rescue IOError => e
          log "Timer: IOError", level: :warning
        rescue Errno::ECONNRESET
          log "Timer: Connection reset by peer", level: :warning
        rescue Errno::EPIPE => e
          log "Timer: Broken pipe", level: :warning
        rescue StandardError => e
          distribute_error e, level: :internal
        end
      ensure
        next_time += interval
        duration = next_time - Time.now.to_f
        task.sleep duration
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
          str = "No acknowledgements for #{message.type} #{message.m_id_short} within #{timeout} seconds"
          log str, level: :error
          begin
            close
          ensure
            distribute_error MissingAcknowledgment.new(str)
          end
        end
      end
    end

    def check_watchdog_timeout now
      timeout = @site_settings['timeouts']['watchdog']
      latest = @latest_watchdog_received + timeout
      left = latest - now
      if left < 0
        str = "No Watchdog received within #{timeout} seconds"
        log str, level: :warning
        distribute MissingWatchdog.new(str)
      end
    end

    def log str, options={}
      super str, options.merge(ip: @ip, port: @port, site_id: @site_id)
    end

    def get_schemas
      schemas = { core: RSMP::Schema.latest_core_version } # use latest core
      schemas[:core] = core_version if core_version
      schemas[sxl] = RSMP::Schema.sanitize_version(sxl_version.to_s) if sxl && sxl_version
      schemas
    end

    def send_message message, reason=nil, validate: true, force: false
      raise NotReady unless connected? unless force
      raise IOError unless @protocol
      message.direction = :out
      message.generate_json
      message.validate get_schemas unless validate==false
      @protocol.write_lines message.json
      expect_acknowledgement message
      distribute message
      log_send message, reason
    rescue EOFError, IOError
      buffer_message message
    rescue SchemaError, RSMP::Schema::Error => e
      schemas_string = e.schemas.map {|schema| "#{schema.first}: #{schema.last}"}.join(", ")
      str = "Could not send #{message.type} because schema validation failed (#{schemas_string}): #{e.message}"
      log str, message: message, level: :error
      distribute_error e.exception("#{str} #{message.json}")
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
      @node.process_deferred
    end

    def verify_sequence message
      expect_version_message(message) unless @version_determined
    end

    def process_packet json
      attributes = Message.parse_attributes json
      message = Message.build attributes, json
      message.validate(get_schemas) if should_validate_ingoing_message?(message)
      verify_sequence message
      with_deferred_distribution do
        distribute message
        process_message message
      end
      process_deferred
      message
    rescue InvalidPacket => e
      str = "Received invalid package, must be valid JSON but got #{json.size} bytes: #{e.message}"
      distribute_error e.exception(str)
      log str, level: :warning
      nil
    rescue MalformedMessage => e
      str = "Received malformed message, #{e.message}"
      distribute_error e.exception(str)
      log str, message: Malformed.new(attributes), level: :warning
      # cannot send NotAcknowledged for a malformed message since we can't read it, just ignore it
      nil
    rescue SchemaError, RSMP::Schema::Error => e
      schemas_string = e.schemas.map {|schema| "#{schema.first}: #{schema.last}"}.join(", ")
      reason = "schema errors (#{schemas_string}): #{e.message}"
      str = "Received invalid #{message.type}"
      distribute_error e.exception(str), message: message
      dont_acknowledge message, str, reason
      message
    rescue InvalidMessage => e
      reason = "#{e.message}"
      str = "Received invalid #{message.type},"
      distribute_error e.exception("#{str} #{message.json}"), message: message
      dont_acknowledge message, str, reason
      message
    rescue FatalError => e
      reason = e.message
      str = "Rejected #{message.type},"
      distribute_error e.exception(str), message: message
      dont_acknowledge message, str, reason
      close
      message
    ensure
      @node.clear_deferred
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

    def core_versions
      version = @site_settings["core_version"]
      if version == 'latest'
        [RSMP::Schema.latest_core_version]
      elsif version
        [version]
      else
        RSMP::Schema.core_versions
      end
    end

    def check_core_version message
      versions = core_versions
      # find versions that both we and the client support
      candidates = message.versions & versions
      if candidates.any?
        @core_version = candidates.sort_by { |v| Gem::Version.new(v) }.last  # pick latest version
      else
        reason = "RSMP versions [#{message.versions.join(', ')}] requested, but only [#{versions.join(', ')}] supported."
        dont_acknowledge message, "Version message rejected", reason, force: true
        raise HandshakeError.new reason
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

    def dont_acknowledge original, prefix=nil, reason=nil, force: true
      raise InvalidArgument unless original
      str = [prefix,reason].join(' ')
      log str, message: original, level: :warning if reason
      message = MessageNotAck.new({
        "oMId" => original.m_id,
        "rea" => reason || "Unknown reason"
      })
      message.original = original.clone
      send_message message, "for #{original.type} #{original.m_id_short}", force: force
    end

    def wait_for_state state, timeout:
      states = [state].flatten
      return if states.include?(@state)
      wait_for_condition(@state_condition,timeout: timeout) do
        states.include?(@state)
      end
      @state
    rescue RSMP::TimeoutError
      raise RSMP::TimeoutError.new "Did not reach state #{state} within #{timeout}s"
    end

    def send_version site_id, core_versions
      if core_versions=='latest'
        versions = [RSMP::Schema.latest_core_version]
      elsif core_versions=='all'
        versions = RSMP::Schema.core_versions
      else
        versions = [core_versions].flatten
      end
      versions_array = versions.map {|v| {"vers" => v} }

      site_id_array = [site_id].flatten.map {|id| {"sId" => id} }

      version_response = Version.new({
        "RSMP"=>versions_array,
        "siteId"=>site_id_array,
        "SXL"=>sxl_version.to_s
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

        case original.type
        when "Version"
          version_acknowledged
        when "StatusSubscribe"
          status_subscribe_acknowledged original
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

    def handshake_complete
      set_state :ready
    end

    def version_acknowledged
    end

    def author
      @node.site_id
    end

    def send_and_optionally_collect message, options, &block
      collect_options = options[:collect] || options[:collect!]
      if collect_options
        task = @task.async do |task|
          task.annotate 'send_and_optionally_collect'
          collector = yield collect_options     # call block to create collector
          collector.collect
          collector.ok! if options[:collect!]   # raise any errors if the bang version was specified
          collector
        end

        send_message message, validate: options[:validate]
        { sent: message, collector: task.wait }
      else
        send_message message, validate: options[:validate]
        return { sent: message }
      end
    end

    def set_nts_message_attributes message
      message.attributes['ntsOId'] = (main && main.ntsOId) ? main.ntsOId : ''
      message.attributes['xNId'] = (main && main.xNId) ? main.xNId : ''
    end

    # Use Gem class to check version requirement
    # Requirement must be a string like '1.1', '>=1.0.3' or '<2.1.4',
    # or list of strings, like ['<=1.4','<1.5']
    def self.version_meets_requirement? version, requirement
      Gem::Requirement.new(requirement).satisfied_by?(Gem::Version.new(version))
    end

    def status_subscribe_acknowledged original
      component = find_component original.attribute('cId')
      return unless component
      short = Message.shorten_m_id original.m_id
      subscribe_list = original.attributes['sS']
      log "StatusSubscribe #{short} acknowledged, allowing repeated status values for #{subscribe_list}", level: :info
      component.allow_repeat_updates subscribe_list
    end
  end
end