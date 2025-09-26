module RSMP
  module SupervisorProxyExtensions
    module Connection
      def run
        loop do
          connect
          start_reader
          start_handshake
          wait_for_reader
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

      def connect
        log "Connecting to supervisor at #{@ip}:#{@port}", level: :info
        change_state :connecting
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
        timeout = connect_timeout
        task.with_timeout timeout do
          @socket = @endpoint.connect
        end
        delay = @site_settings.dig('intervals', 'after_connect')
        task.sleep delay if delay
        @stream = IO::Stream::Buffered.new(@socket)
        @protocol = RSMP::Protocol.new(@stream)
        change_state :connected
      rescue Errno::ECONNREFUSED => e
        log 'Connection refused', level: :warning
        raise e
      end

      def reconnect_delay?
        return false if @site_settings['intervals']['reconnect'] == :no

        interval = @site_settings['intervals']['reconnect']
        log "Will try to reconnect again every #{interval} seconds...", level: :info
        @logger.mute @ip, @port
        @task.sleep interval
        true
      end

      private

      def connect_timeout
        @site_settings.dig('timeouts', 'connect') || 1.1
      end

      def send_initial_state
        send_all_aggregated_status
        send_active_alarms
      end
    end
  end
end
