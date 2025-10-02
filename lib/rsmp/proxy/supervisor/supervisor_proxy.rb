# Handles a site connection to a remote supervisor

require 'digest'

module RSMP
  class SupervisorProxy < Proxy
    include Modules::Status
    include Modules::Commands
    include Modules::Alarms
    include Modules::AggregatedStatus

    attr_reader :supervisor_id, :site

    def initialize(options)
      super(options.merge(node: options[:site]))
      @site = options[:site]
      @site_settings = @site.site_settings.clone
      @ip = options[:ip]
      @port = options[:port]
      @status_subscriptions = {}
      @sxl = @site_settings['sxl']
      @synthetic_id = Supervisor.build_id_from_ip_port @ip, @port
    end

    # handle communication
    # if disconnected, then try to reconnect
    def run
      loop do
        connect
        start_reader
        start_handshake
        wait_for_reader # run until disconnected
        break unless reconnect_delay?
      rescue Restart
        @logger.mute @ip, @port
        raise
      rescue RSMP::ConnectionError => e
        log e, level: :error
        break unless reconnect_delay?
      rescue StandardError => e
        distribute_error e, level: :internal
        break unless reconnect_delay?
      ensure
        close
        stop_subtasks
      end
    end

    def start_handshake
      send_version @site_settings['site_id'], core_versions
    end

    # connect to the supervisor and initiate handshake supervisor
    def connect
      log "Connecting to supervisor at #{@ip}:#{@port}", level: :info
      self.state = :connecting
      connect_tcp
      @logger.unmute @ip, @port
      log "Connected to supervisor at #{@ip}:#{@port}", level: :info
    rescue SystemCallError => e
      raise ConnectionError, "Could not connect to supervisor at #{@ip}:#{@port}: Errno #{e.errno} #{e}"
    rescue StandardError => e
      raise ConnectionError, "Error while connecting to supervisor at #{@ip}:#{@port}: #{e}"
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
      self.state = :connected
    rescue Errno::ECONNREFUSED => e # rescue to avoid log output
      log 'Connection refused', level: :warning
      raise e
    end

    def handshake_complete
      sanitized_sxl_version = RSMP::Schema.sanitize_version(sxl_version)
      log "Connection to supervisor established, using core #{@core_version}, #{sxl} #{sanitized_sxl_version}",
          level: :info
      self.state = :ready
      start_watchdog
      if @site_settings['send_after_connect']
        send_all_aggregated_status
        send_active_alarms
      end
      super
    end

    def process_message(message)
      case message
      when StatusResponse, StatusUpdate, AggregatedStatus, AlarmIssue
        will_not_handle message
      when AggregatedStatusRequest
        process_aggregated_status_request message
      when CommandRequest
        process_command_request message
      when CommandResponse
        process_command_response message
      when StatusRequest
        process_status_request message
      when StatusSubscribe
        process_status_subcribe message
      when StatusUnsubscribe
        process_status_unsubcribe message
      when Alarm, AlarmAcknowledged, AlarmSuspend, AlarmResume, AlarmRequest
        process_alarm message
      else
        super
      end
    rescue UnknownComponent, UnknownCommand, UnknownStatus,
           MessageRejected, MissingAttribute => e
      dont_acknowledge message, '', e.to_s
    end

    def acknowledged_first_ingoing(message)
      case message.type
      when 'Watchdog'
        handshake_complete
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

    def timer(now)
      super
      status_update_timer now if ready?
    end

    def sxl_version
      @site_settings['sxl_version'].to_s
    end

    def process_version(message)
      return extraneous_version message if @version_determined

      check_core_version message
      check_sxl_version message
      @site_id = Supervisor.build_id_from_ip_port @ip, @port
      version_accepted message
    end

    def check_sxl_version(message); end

    def main
      @site.main
    end
  end
end
