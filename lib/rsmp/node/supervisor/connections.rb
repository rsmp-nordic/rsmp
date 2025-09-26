module RSMP
  module SupervisorExtensions
    module Lifecycle
      def run
        log "Starting supervisor on port #{@supervisor_settings['port']}",
            level: :info,
            timestamp: @clock.now

        @endpoint = IO::Endpoint.tcp('0.0.0.0', @supervisor_settings['port'])
        start_accept_loop
        @ready_condition.signal
        @accept_task.wait
      rescue StandardError => e
        distribute_error e, level: :internal
      end

      def stop
        log "Stopping supervisor #{@supervisor_settings['site_id']}", level: :info

        @accept_task&.stop
        @accept_task = nil

        @endpoint = nil
        super
      end

      private

      def start_accept_loop
        @accept_task = Async::Task.current.async do |task|
          task.annotate 'supervisor accept loop'
          @endpoint.accept do |socket|
            handle_connection(socket)
          rescue StandardError => e
            distribute_error e, level: :internal
          end
        rescue Async::Stop
          log 'Accept loop stopped', level: :debug
        rescue StandardError => e
          distribute_error e, level: :internal
        end
      end
    end

    module ConnectionHandling
      def handle_connection(socket)
        remote_port = socket.remote_address.ip_port
        remote_hostname = socket.remote_address.ip_address
        remote_ip = socket.remote_address.ip_address

        info = { ip: remote_ip, port: remote_port, hostname: remote_hostname, now: Clock.now }
        if accept?(socket, info)
          accept_connection socket, info
        else
          reject_connection socket, info
        end
      rescue ConnectionError, HandshakeError => e
        log "Rejected connection from #{remote_ip}:#{remote_port}, #{e}", level: :warning
        distribute_error e
      rescue StandardError => e
        log "Connection: #{e}", exception: e, level: :error
        distribute_error e, level: :internal
      ensure
        close socket, info
      end

      def accept?(_socket, _info)
        true
      end

      def reject_connection(_socket, info)
        log 'Site rejected', ip: info[:ip], level: :info
      end

      def close(socket, info)
        if info
          log "Connection to #{format_ip_and_port(info)} closed", ip: info[:ip], level: :info, timestamp: Clock.now
        else
          log 'Connection closed', level: :info, timestamp: Clock.now
        end

        socket.close
      end
    end

    module ConnectionAcceptance
      def authorize_ip(ip)
        return if @supervisor_settings['ips'] == 'all'
        return if @supervisor_settings['ips'].include? ip

        raise ConnectionError, 'guest ip not allowed'
      end

      def check_max_sites
        max = @supervisor_settings['max_sites']
        return unless max
        return unless @proxies.size >= max

        raise ConnectionError, "maximum of #{max} sites already connected"
      end

      def peek_version_message(protocol)
        json = protocol.peek_line
        attributes = Message.parse_attributes json
        Message.build attributes, json
      end

      def accept_connection(socket, info)
        log_site_connection info
        authorize_connection info

        stream, protocol = build_stream_and_protocol(socket)
        settings = build_connection_settings(socket, stream, protocol, info)
        version_message = peek_version_message protocol

        proxy = prepare_proxy(version_message, settings)
        validate_proxy(proxy, version_message)
        run_proxy proxy
      ensure
        site_ids_changed
        stop if @supervisor_settings['one_shot']
      end

      private

      def log_site_connection(info)
        log "Site connected from #{format_ip_and_port(info)}",
            ip: info[:ip],
            port: info[:port],
            level: :info,
            timestamp: Clock.now
      end

      def authorize_connection(info)
        authorize_ip info[:ip]
      end

      def build_stream_and_protocol(socket)
        stream = IO::Stream::Buffered.new(socket)
        [stream, RSMP::Protocol.new(stream)]
      end

      def build_connection_settings(socket, stream, protocol, info)
        {
          supervisor: self,
          ip: info[:ip],
          port: info[:port],
          task: @task,
          collect: @collect,
          socket: socket,
          stream: stream,
          protocol: protocol,
          info: info,
          logger: @logger,
          archive: @archive
        }
      end

      def prepare_proxy(version_message, settings)
        id = site_id_from_version(version_message)
        proxy = find_site id
        if proxy
          ensure_proxy_available(proxy, id)
          proxy.revive settings
        else
          check_max_sites
          proxy = build_proxy(settings.merge(site_id: id))
          register_proxy proxy
        end
        proxy
      end

      def site_id_from_version(version_message)
        version_message.attribute('siteId').first['sId']
      end

      def ensure_proxy_available(proxy, id)
        return unless proxy.connected?

        raise ConnectionError, "Site #{id} alredy connected from port #{proxy.port}"
      end

      def validate_proxy(proxy, version_message)
        proxy.setup_site_settings
        proxy.check_core_version version_message
        log "Validating using core version #{proxy.core_version}", level: :debug
      end

      def run_proxy(proxy)
        proxy.start
        proxy.wait
      end
    end

    module Connections
      include Lifecycle
      include ConnectionHandling
      include ConnectionAcceptance
    end
  end
end
