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
      self.state = :connected
      start_reader
      wait_for_reader # run until disconnected
    rescue RSMP::ConnectionError => e
      log e, level: :error
    rescue StandardError => e
      distribute_error e, level: :internal
    ensure
      close
    end

    def run_outbound_connection
      loop do
        setup_site_settings
        connect
        start_reader
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

    def connect
      log "Connecting to site #{@site_id} at #{@ip}:#{@port}", level: :info
      self.state = :connecting
      open_socket
      self.state = :connected
      @logger.unmute @ip, @port
      log "Connected to site #{@site_id} at #{@ip}:#{@port}", level: :info
    rescue SystemCallError => e
      raise ConnectionError, "Could not connect to site #{@site_id} at #{@ip}:#{@port}: Errno #{e.errno} #{e}"
    rescue StandardError => e
      raise ConnectionError, "Error while connecting to site #{@site_id} at #{@ip}:#{@port}: #{e}"
    end

    def open_socket
      endpoint = IO::Endpoint.tcp(@ip, @port)
      timeout = @site_settings.dig('timeouts', 'connect') || 1.1
      task.with_timeout(timeout) { @socket = endpoint.connect }
      @stream = IO::Stream::Buffered.new(@socket)
      @protocol = RSMP::Protocol.new(@stream)
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
