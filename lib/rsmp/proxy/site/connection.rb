module RSMP
  # Connection management for supervisor-side site proxies.
  module SiteProxyConnection
    # handle communication
    # when we're created, the socket is already open
    def run
      if @protocol
        run_accepted_connection
      else
        run_outbound_connection
      end
    end

    def run_accepted_connection
      begin_session
      self.state = :connected
      start_reader
      ended = wait_for_reader
      close_from_result(ended)
    ensure
      close(reason: :internal_failure) if $ERROR_INFO
      close
    end

    def run_outbound_connection
      loop do
        setup_site_settings
        connected = connect
        unless connected.success?
          publish_connection_attempt_failure(connected.failure)
          break unless reconnect_delay?

          next
        end
        start_reader
        close_from_result(wait_for_reader)
        break unless reconnect_delay?
      ensure
        close(reason: :internal_failure) if $ERROR_INFO
        close
      end
    end

    def connect
      log "Connecting to site #{@site_id} at #{@ip}:#{@port}", level: :info
      begin_session
      self.state = :connecting
      opened = open_socket
      return opened if opened.failure?

      self.state = :connected
      @logger.unmute @ip, @port
      log "Connected to site #{@site_id} at #{@ip}:#{@port}", level: :info
      Result.success(self)
    end

    def open_socket
      endpoint = IO::Endpoint.tcp(@ip, @port)
      timeout = @site_settings.dig('timeouts', 'connect') || 1.1
      task.with_timeout(timeout) { @socket = endpoint.connect }
      @stream = IO::Stream::Buffered.new(@socket)
      @protocol = RSMP::Protocol.new(@stream)
      Result.success(self)
    rescue SystemCallError, SocketError, IOError, Async::TimeoutError => e
      Result.failure(
        :connection_failed,
        message: "Could not connect to site #{@site_id} at #{@ip}:#{@port}: #{e.message}",
        source: :transport,
        context: { ip: @ip, port: @port, session_id: @session_id },
        cause: e
      )
    end

    def reconnect_delay?
      return false if @site_settings['intervals']['reconnect'] == :no

      interval = @site_settings['intervals']['reconnect'] || 0.1
      log "Will try to reconnect again every #{interval} seconds...", level: :info
      @logger.mute @ip, @port
      @task.sleep interval
      true
    end
  end
end
