# RSMP supervisor (server)
# The supervisor waits for sites to connect.
# Connections to sites are handles via site proxies.

module RSMP
  class Supervisor < Node
    attr_reader :rsmp_versions, :site_id, :supervisor_settings, :proxies, :logger

    def initialize options={}
      handle_supervisor_settings options
      super options
      @proxies = []
      @site_id_condition = Async::Notification.new
    end

    def site_id
      @supervisor_settings['site_id']
    end

    def handle_supervisor_settings options
      @supervisor_settings = {
        'port' => 12111,
        'rsmp_versions' => ['3.1.1','3.1.2','3.1.3','3.1.4'],
        'timer_interval' => 0.1,
        'watchdog_interval' => 1,
        'watchdog_timeout' => 2,
        'acknowledgement_timeout' => 2,
        'command_response_timeout' => 1,
        'status_response_timeout' => 1,
        'status_update_timeout' => 1,
        'site_connect_timeout' => 2,
        'site_ready_timeout' => 1,
        'stop_after_first_session' => false,
        'sites' => {
          :any => {}
        }
      }
      
      if options[:supervisor_settings]
        converted = options[:supervisor_settings].map { |k,v| [k.to_s,v] }.to_h   #convert symbol keys to string keys
        converted.compact!
        @supervisor_settings.merge! converted
      end

      required = [:port, :rsmp_versions, :watchdog_interval, :watchdog_timeout,
                  :acknowledgement_timeout, :command_response_timeout]
      check_required_settings @supervisor_settings, required

      @rsmp_versions = @supervisor_settings["rsmp_versions"]
    end

    def start_action
      @endpoint = Async::IO::Endpoint.tcp('0.0.0.0', @supervisor_settings["port"])
      @endpoint.accept do |socket|
        handle_connection(socket)
      end
    rescue SystemCallError => e # all ERRNO errors
      log "Exception: #{e.to_s}", level: :error
    rescue StandardError => e
      log ["Exception: #{e.inspect}",e.backtrace].flatten.join("\n"), level: :error
    end

    def stop
      log "Stopping supervisor #{@supervisor_settings["site_id"]}", level: :info
      @proxies.each { |proxy| proxy.stop }
      @proxies.clear
      super
      @tcp_server.close if @tcp_server
      @tcp_server = nil
    end

    def handle_connection socket
      remote_port = socket.remote_address.ip_port
      remote_hostname = socket.remote_address.ip_address
      remote_ip = socket.remote_address.ip_address

      info = {ip:remote_ip, port:remote_port, hostname:remote_hostname, now:RSMP.now_string()}
      if accept? socket, info
        connect socket, info
      else
        reject socket, info
      end
    rescue SystemCallError => e # all ERRNO errors
      log "Exception: #{e.to_s}", level: :error
    rescue StandardError => e
      log "Exception: #{e}", exception: e, level: :error
    ensure
      close socket, info
    end

    def starting
      log "Starting supervisor on port #{@supervisor_settings["port"]}", 
          level: :info,
          timestamp: RSMP.now_object
    end

    def accept? socket, info
      true
    end

    def build_proxy settings
      SiteProxy.new settings
    end

    def format_ip_and_port info
      if @logger.settings['hide_ip_and_port']
         '********'
      else
         "#{info[:ip]}:#{info[:port]}"
      end
    end

    def connect socket, info
      log "Site connected from #{format_ip_and_port(info)}",
          ip: info[:ip],
          port: info[:port],
          level: :info,
          timestamp: RSMP.now_object

      proxy = build_proxy({
        supervisor: self,
        task: @task,
        settings: @supervisor_settings[:sites],
        socket: socket,
        info: info,
        logger: @logger,
        archive: @archive
      })
      @proxies.push proxy
      
      proxy.run     # will run until the site disconnects
    ensure
      @proxies.delete proxy
      site_ids_changed

      stop if @supervisor_settings['stop_after_first_session']
    end

    def site_ids_changed
      @site_id_condition.signal
    end

    def reject socket, info
      log "Site rejected", ip: info[:ip], level: :info
    end

    def close socket, info
      if info
        log "Connection to #{format_ip_and_port(info)} closed", ip: info[:ip], level: :info, timestamp: RSMP.now_object
      else
        log "Connection closed", level: :info, timestamp: RSMP.now_object
      end

      socket.close
    end

    def site_connected? site_id
      return find_site(site_id) != nil
    end

    def find_site site_id
      @proxies.each do |site|
        return site if site_id == :any || site.site_id == site_id
      end
      nil
    end

    def wait_for_site site_id, timeout
      site = find_site site_id
      return site if site
      wait_for(@site_id_condition,timeout) { find_site site_id }
    rescue Async::TimeoutError
      nil
    end

    def wait_for_site_disconnect site_id, timeout
      wait_for(@site_id_condition,timeout) { true unless find_site site_id }
    rescue Async::TimeoutError
      false
    end

    def check_site_id site_id
      check_site_already_connected site_id
      return find_allowed_site_setting site_id
    end

    def check_site_already_connected site_id
      raise FatalError.new "Site #{site_id} already connected" if find_site(site_id)
    end

    def find_allowed_site_setting site_id
      return {} unless @supervisor_settings['sites']
      @supervisor_settings['sites'].each_pair do |id,settings|
        if id == :any || id == site_id
          return settings
        end
      end
      raise FatalError.new "site id #{site_id} rejected"
    end

    def aggregated_status_changed site_proxy, component
    end

    def self.build_id_from_ip_port ip, port
      Digest::MD5.hexdigest("#{ip}:#{port}")[0..8]
    end

  end
end