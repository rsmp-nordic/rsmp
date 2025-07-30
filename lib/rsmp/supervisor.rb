# RSMP supervisor (server)
# The supervisor waits for sites to connect.
# Connections to sites are handles via site proxies.

module RSMP
  class Supervisor < Node
    attr_reader :core_version, :site_id, :supervisor_settings, :proxies, :logger

    def initialize options={}
      handle_supervisor_settings( options[:supervisor_settings] || {} )
      super options
      @proxies = []
      @site_id_condition = Async::Notification.new
    end

    def site_id
      @supervisor_settings['site_id']
    end

    def handle_supervisor_settings supervisor_settings
      defaults = {
        'port' => 12111,
        'ips' => 'all',
        'guest' => {
          'sxl' => 'tlc',
          'type' => 'tlc',
          'intervals' => {
            'timer' => 1,
            'watchdog' => 1
          },
          'timeouts' => {
            'watchdog' => 2,
            'acknowledgement' => 2
          }
        }
      }

      # merge options into defaults
      @supervisor_settings = defaults.deep_merge(supervisor_settings)
      @core_version = @supervisor_settings["guest"]["core_version"]
      check_site_sxl_types
    end

    def check_site_sxl_types
      sites = @supervisor_settings['sites'].clone || {}
      sites['guest'] = @supervisor_settings['guest']
      sites.each do |site_id,settings|
        unless settings
          raise RSMP::ConfigurationError.new("Configuration for site '#{site_id}' is empty")
        end
        sxl = settings['sxl']
        unless sxl
          raise RSMP::ConfigurationError.new("Configuration error for site '#{site_id}': No SXL specified")
        end
        RSMP::Schema.find_schemas! sxl if sxl
      rescue RSMP::Schema::UnknownSchemaError => e
        raise RSMP::ConfigurationError.new("Configuration error for site '#{site_id}': #{e}")
      end
    end

    # listen for connections
    # Async::IO::Endpoint#accept createa an async task that we will wait for
    def run
      log "Starting supervisor on port #{@supervisor_settings["port"]}",
          level: :info,
          timestamp: @clock.now

      @endpoint = Async::IO::Endpoint.tcp('0.0.0.0', @supervisor_settings["port"])
      tasks = @endpoint.accept do |socket|  # creates async tasks
        handle_connection(socket)
      rescue StandardError => e
        distribute_error e, level: :internal
      end
      tasks.each { |task| task.wait }
    rescue StandardError => e
      distribute_error e, level: :internal
    end

    # stop
    def stop
      log "Stopping supervisor #{@supervisor_settings["site_id"]}", level: :info
      super
    end

    # handle an incoming connction by either accepting of rejecting it
    def handle_connection socket
      remote_port = socket.remote_address.ip_port
      remote_hostname = socket.remote_address.ip_address
      remote_ip = socket.remote_address.ip_address

      info = {ip:remote_ip, port:remote_port, hostname:remote_hostname, now:Clock.now}
      if accept? socket, info
        accept_connection socket, info
      else
        reject_connection socket, info
      end
    rescue ConnectionError, HandshakeError => e
      log "Rejected connection from #{remote_ip}:#{remote_port}, #{e.to_s}", level: :warning
      distribute_error e
    rescue StandardError => e
      log "Connection: #{e.to_s}", exception: e, level: :error
      distribute_error e, level: :internal
    ensure
      close socket, info
    end

    def accept? socket, info
      true
    end

    def format_ip_and_port info
      if @logger.settings['hide_ip_and_port']
         '********'
      else
         "#{info[:ip]}:#{info[:port]}"
      end
    end

    def authorize_ip ip
      return if @supervisor_settings['ips'] == 'all'
      return if @supervisor_settings['ips'].include? ip
      raise ConnectionError.new('guest ip not allowed')
    end

    def check_max_sites
      max = @supervisor_settings['max_sites']
      if max
        if @proxies.size >= max
          raise ConnectionError.new("maximum of #{max} sites already connected")
        end
      end
    end

    def peek_version_message protocol
      json = protocol.peek_line
      attributes = Message.parse_attributes json
       Message.build attributes, json
    end

    # accept an incoming connecting by creating and starting a proxy
    def accept_connection socket, info
      log "Site connected from #{format_ip_and_port(info)}",
          ip: info[:ip],
          port: info[:port],
          level: :info,
          timestamp: Clock.now

      authorize_ip info[:ip]

      stream = Async::IO::Stream.new socket
      protocol = Async::IO::Protocol::Line.new stream, Proxy::WRAPPING_DELIMITER

      settings = {
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

      version_message = peek_version_message protocol
      id = version_message.attribute('siteId').first['sId']

      proxy = find_site id
      if proxy
        if proxy.connected?
          raise ConnectionError.new("Site #{id} alredy connected from port #{proxy.port}")
        else
          proxy.revive settings
        end
      else
        check_max_sites
        
        # Determine the appropriate proxy type based on site settings
        site_settings = check_site_id id
        if site_settings && site_settings['type'] == 'tlc'
          proxy = TLC::TrafficControllerProxy.new settings.merge(site_id:id)
        else
          proxy = SiteProxy.new settings.merge(site_id:id)
        end
        
        @proxies.push proxy
      end

      proxy.setup_site_settings
      proxy.check_core_version version_message
      log "Validating using core version #{proxy.core_version}", level: :debug

      proxy.start     # will run until the site disconnects
      proxy.wait
    ensure
      site_ids_changed
      stop if @supervisor_settings['one_shot']
    end

    def site_ids_changed
      @site_id_condition.signal
    end

    def reject_connection socket, info
      log "Site rejected", ip: info[:ip], level: :info
    end

    def close socket, info
      if info
        log "Connection to #{format_ip_and_port(info)} closed", ip: info[:ip], level: :info, timestamp: Clock.now
      else
        log "Connection closed", level: :info, timestamp: Clock.now
      end

      socket.close
    end

    def site_connected? site_id
      return find_site(site_id) != nil
    end

    def find_site_from_ip_port ip, port
      @proxies.each do |site|
        return site if site.ip == ip && site.port == port
      end
      nil
    end

   def find_site site_id
      @proxies.each do |site|
        return site if site_id == :any || site.site_id == site_id
      end
      nil
    end

    def wait_for_site site_id, timeout:
      site = find_site site_id
      return site if site
      wait_for_condition(@site_id_condition,timeout:timeout) do
        find_site site_id
      end

    rescue Async::TimeoutError
      if site_id == :any
        str = "No site connected"
      else
        str = "Site '#{site_id}' did not connect"
      end
      raise RSMP::TimeoutError.new "#{str} within #{timeout}s"
    end

    def wait_for_site_disconnect site_id, timeout:
      wait_for_condition(@site_id_condition,timeout:timeout) { true unless find_site site_id }
    rescue Async::TimeoutError
      raise RSMP::TimeoutError.new "Site '#{site_id}' did not disconnect within #{timeout}s"
    end

    def check_site_id site_id
      #check_site_already_connected site_id
      return site_id_to_site_setting site_id
    end

    def check_site_already_connected site_id
      site = find_site(site_id)
      raise HandshakeError.new "Site '#{site_id}' already connected" if site != nil && site != self
    end

    def site_id_to_site_setting site_id
      return {} unless @supervisor_settings['sites']
      @supervisor_settings['sites'].each_pair do |id,settings|
        if id == 'guest' || id == site_id
          return settings
        end
      end
      raise HandshakeError.new "site id #{site_id} unknown"
    end

    def ip_to_site_settings ip
      @supervisor_settings['sites'][ip] || @supervisor_settings['sites']['guest']
    end

    def aggregated_status_changed site_proxy, component
    end

    def self.build_id_from_ip_port ip, port
      Digest::MD5.hexdigest("#{ip}:#{port}")[0..8]
    end

  end
end