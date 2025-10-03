# frozen_string_literal: true

module RSMP
  class Supervisor < Node
    module Modules
      # Handles incoming connections from sites
      module Connection
        def handle_connection(socket)
          remote_port = socket.remote_address.ip_port
          remote_hostname = socket.remote_address.ip_address
          remote_ip = socket.remote_address.ip_address

          info = { ip: remote_ip, port: remote_port, hostname: remote_hostname, now: Clock.now }
          if accept? socket, info
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

        def format_ip_and_port(info)
          if @logger.settings['hide_ip_and_port']
            '********'
          else
            "#{info[:ip]}:#{info[:port]}"
          end
        end

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

        def build_proxy_settings(socket, info)
          stream = IO::Stream::Buffered.new(socket)
          protocol = RSMP::Protocol.new stream

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

        def retrieve_site_id(protocol)
          version_message = peek_version_message protocol
          version_message.attribute('siteId').first['sId']
        end

        def setup_proxy(proxy, settings, id)
          if proxy
            raise ConnectionError, "Site #{id} alredy connected from port #{proxy.port}" if proxy.connected?

            proxy.revive settings
          else
            check_max_sites
            proxy = build_proxy settings.merge(site_id: id)
            @proxies.push proxy
          end
          proxy
        end

        def accept_connection(socket, info)
          log "Site connected from #{format_ip_and_port(info)}",
              ip: info[:ip],
              port: info[:port],
              level: :info,
              timestamp: Clock.now

          authorize_ip info[:ip]

          settings = build_proxy_settings(socket, info)
          id = retrieve_site_id(settings[:protocol])
          proxy = setup_proxy(find_site(id), settings, id)

          proxy.setup_site_settings
          proxy.check_core_version peek_version_message(settings[:protocol])
          log "Validating using core version #{proxy.core_version}", level: :debug

          proxy.start
          proxy.wait
        ensure
          site_ids_changed
          stop if @supervisor_settings['one_shot']
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
    end
  end
end
