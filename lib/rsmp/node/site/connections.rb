module RSMP
  # Connection handling for site instances.
  module SiteConnections
    def build_proxies
      return if server_role?

      @site_settings['supervisors'].each do |supervisor_settings|
        @proxies << SupervisorProxy.new(supervisor_proxy_options(supervisor_settings))
      end
    end

    def listen_for_supervisors
      ip = @site_settings['ip'] || '0.0.0.0'
      port = @site_settings['port']
      log "Starting #{site_type_name} listener on #{ip}:#{port}", level: :info, timestamp: @clock.now
      @endpoint = IO::Endpoint.tcp(ip, port)
      @accept_task = Async::Task.current.async do |task|
        task.annotate 'site accept loop'
        accept_supervisor_connections
      end

      @ready_condition.signal
      @accept_task.wait
    end

    def accept_supervisor_connections
      @endpoint.accept do |socket|
        accept_supervisor_connection socket
      rescue StandardError => e
        distribute_error e, level: :internal
      end
    rescue Async::Stop
      # Expected during shutdown - no action needed
    rescue StandardError => e
      distribute_error e, level: :internal
    end

    def accept_supervisor_connection(socket)
      remote_port = socket.remote_address.ip_port
      remote_ip = socket.remote_address.ip_address
      proxy = SupervisorProxy.new(accepted_supervisor_options(socket, remote_ip, remote_port))
      @proxies << proxy
      @proxies_condition.signal
      proxy.start
      proxy.wait
    end

    def connect_to_supervisor(_task, supervisor_settings)
      proxy = build_proxy(supervisor_proxy_options(supervisor_settings))
      @proxies << proxy
      proxy.start
      @proxies_condition.signal
    end

    private

    def supervisor_proxy_options(supervisor_settings)
      {
        site: self,
        task: @task,
        settings: @site_settings,
        ip: supervisor_settings['ip'],
        port: supervisor_settings['port'],
        logger: @logger,
        archive: @archive,
        collect: @collect
      }
    end

    def accepted_supervisor_options(socket, remote_ip, remote_port)
      stream = IO::Stream::Buffered.new(socket)
      supervisor_proxy_options('ip' => remote_ip, 'port' => remote_port).merge(
        socket: socket,
        stream: stream,
        protocol: RSMP::Protocol.new(stream),
        info: { ip: remote_ip, port: remote_port, hostname: remote_ip, now: Clock.now }
      )
    end
  end
end
