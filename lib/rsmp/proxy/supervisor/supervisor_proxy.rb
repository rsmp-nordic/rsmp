require 'digest'

module RSMP
  # Proxy used by sites to connect to a remote supervisor.
  class SupervisorProxy < Proxy
    include Modules::Status
    include Modules::Commands
    include Modules::Alarms
    include Modules::AggregatedStatus
    include Modules::MessageBuffer

    attr_reader :supervisor_id, :site, :message_buffer

    def initialize(options)
      super(options.merge(node: options[:site]))
      @site = options[:site]
      @site_settings = @site.site_settings.clone
      @ip = options[:ip]
      @port = options[:port]
      @status_subscriptions = {}
      @sxls = configured_sxls
      @accepted_sxls = @sxls.dup
      @rejected_sxls = []
      @synthetic_id = Supervisor.build_id_from_ip_port @ip, @port
      @message_buffer = []
    end

    # handle communication
    # if disconnected, then try to reconnect
    def run
      if @protocol
        run_accepted_connection
        return
      end

      loop do
        connected = connect
        unless connected.success?
          publish_connection_attempt_failure(connected.failure)
          break unless reconnect_delay?

          next
        end
        start_reader
        start_handshake
        close_from_result(wait_for_reader)
        break unless reconnect_delay?
      ensure
        close(reason: :internal_failure) if $ERROR_INFO
        close
      end
    end

    def run_accepted_connection
      begin_session
      self.state = :connected
      start_reader
      start_handshake
      close_from_result(wait_for_reader)
    ensure
      close(reason: :internal_failure) if $ERROR_INFO
      close
    end

    def start_handshake
      send_version_request @site_settings['site_id'], core_versions
    end

    def close(...)
      prune_unbuffered_status_subscriptions
      super
    end

    # connect to the supervisor and initiate handshake supervisor
    def connect
      log "Connecting to supervisor at #{@ip}:#{@port}", level: :info
      begin_session
      self.state = :connecting
      opened = connect_tcp
      return opened if opened.failure?

      self.state = :connected
      @logger.unmute @ip, @port
      log "Connected to supervisor at #{@ip}:#{@port}", level: :info
      Result.success(self)
    end

    def stop_task
      super
      @last_status_sent = nil
    end

    def connect_tcp
      @endpoint = IO::Endpoint.tcp(@ip, @port)

      # this timeout is a workaround for connect hanging on windows if the other side is not present yet
      timeout = @site_settings.dig('timeouts', 'connect') || 1.1
      task.with_timeout timeout do
        @socket = @endpoint.connect
      end
      delay = @site_settings.dig('intervals', 'after_connect')
      task.sleep delay if delay

      @stream = IO::Stream::Buffered.new(@socket)
      @protocol = RSMP::Protocol.new(@stream) # rsmp messages are json terminated with a form-feed
      Result.success(self)
    rescue Errno::ECONNREFUSED => e # rescue to avoid log output
      log 'Connection refused', level: :warning
      failed_connection_result(e)
    rescue SystemCallError, SocketError, IOError, Async::TimeoutError => e
      failed_connection_result(e)
    end

    def failed_connection_result(error)
      Result.failure(
        :connection_failed,
        message: "Could not connect to supervisor at #{@ip}:#{@port}: #{error.message}",
        source: :transport,
        context: { ip: @ip, port: @port, session_id: @session_id },
        cause: error
      )
    end

    def handshake_complete
      sxl_summary = accepted_sxls.map { |item| "#{item['name']} #{item['version']}" }.join(', ')
      log "Connection to supervisor established, using core #{@core_version}, SXLs [#{sxl_summary}]",
          level: :info
      self.state = :ready
      start_watchdog
      if @site_settings['send_after_connect']
        send_all_aggregated_status
        send_active_alarms if receive_alarms?
      end
      flush_message_buffer
      super
    end

    def process_message(message)
      case message
      when StatusResponse, StatusUpdate, AggregatedStatus, AlarmIssue
        will_not_handle message
      when AggregatedStatusRequest
        process_aggregated_status_request message
      when CommandResponse
        process_command_response message
      when CommandRequest, StatusRequest, StatusSubscribe, StatusUnsubscribe,
           Alarm, AlarmAcknowledged, AlarmSuspend, AlarmResume, AlarmRequest
        handle_interface_request message
      else
        super
      end
    end

    def handle_interface_request(message)
      interface = sxl_interface_for message
      interface.validate_message! message
      interface.process_message message
    end

    def process_sxl_request(message)
      case message
      when CommandRequest
        process_command_request message
      when StatusRequest
        process_status_request message
      when StatusSubscribe
        process_status_subcribe message
      when StatusUnsubscribe
        process_status_unsubcribe message
      when Alarm, AlarmAcknowledged, AlarmSuspend, AlarmResume, AlarmRequest
        process_alarm message
      end
    end

    def acknowledged_first_ingoing(message)
      case message.type
      when 'Watchdog'
        if core_3_3?
          send_component_list
        else
          handshake_complete
        end
      end
    end

    def reconnect_delay?
      return false if @site_settings['intervals']['reconnect'] == :no

      interval = @site_settings['intervals']['reconnect']
      log "Will try to reconnect again every #{interval} seconds...", level: :info
      @logger.mute @ip, @port
      @task.sleep interval
      true
    end

    def version_accepted(message)
      log "Received Version message, using RSMP #{@core_version}", message: message, level: :log
      start_timer
      acknowledge message
      @version_determined = true
      send_watchdog
    end

    def process_version(message)
      return extraneous_version message if @version_determined

      check_core_version message
      check_sxl_version message
      @site_id = Supervisor.build_id_from_ip_port @ip, @port
      version_accepted message
    end

    def check_sxl_version(message)
      if core_3_3?
        @rejected_sxls, @accepted_sxls = message.sxls.partition { |item| item['rejected'] }
        @receive_alarms = message.attributes.fetch('receiveAlarms', true)
      else
        primary = primary_configured_sxl
        raise HandshakeError, 'Legacy Version response received, but no SXL is configured' unless primary

        @accepted_sxls = [primary]
        @rejected_sxls = []
      end
      build_sxl_interfaces
    end

    def send_component_list
      send_generated_message ComponentList.new('components' => @site.component_list)
    end

    def component_list_acknowledged
      handshake_complete
    end

    def main
      @site.main
    end
  end
end
