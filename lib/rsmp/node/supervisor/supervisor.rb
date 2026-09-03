module RSMP
  # RSMP supervisor (server) that accepts site connections.
  class Supervisor < Node
    include Modules::Configuration
    include Modules::Connection
    include Modules::Sites

    attr_reader :core_version, :supervisor_settings, :proxies, :logger, :ready_condition

    attr_accessor :site_id_condition

    def initialize(options = {})
      handle_supervisor_settings(options[:supervisor_settings] || {})
      super
      @proxies = []
      @ready_condition = Async::Notification.new
      @site_id_condition = Async::Notification.new
    end

    def site_id
      @supervisor_settings['site_id']
    end

    def client_role?
      @supervisor_settings['connection_role'] == 'client'
    end

    def server_role?
      !client_role?
    end

    # listen for connections
    def run
      return connect_to_sites if client_role?

      log "Starting supervisor on port #{@supervisor_settings['port']}",
          level: :info,
          timestamp: @clock.now

      @endpoint = IO::Endpoint.tcp('0.0.0.0', @supervisor_settings['port'])
      barrier = Async::Barrier.new(parent: @task)
      @accept_task = barrier.async do |task|
        task.annotate 'supervisor accept loop'
        @endpoint.accept do |socket|
          handle_connection(socket)
        end
        task.wait_all
      end

      @ready_condition.signal
      barrier.wait
    ensure
      barrier.cancel if barrier && !barrier.empty?
    end

    def connect_to_sites
      log 'Starting supervisor in client connection role',
          level: :info,
          timestamp: @clock.now
      build_outbound_proxies
      @ready_condition.signal
      barrier = Async::Barrier.new(parent: @task)
      @proxies.each { |proxy| proxy.start(parent: barrier) }
      barrier.wait
    ensure
      barrier.cancel if barrier && !barrier.empty?
    end

    def build_outbound_proxies
      site_entries = (@supervisor_settings['sites'] || {}).except('default')
      site_entries.each_pair do |site_id, site_settings|
        endpoints = site_settings['supervisors'] || []
        merged_settings = site_id_to_site_setting site_id
        endpoints.each do |endpoint|
          @proxies << SiteProxy.new({
                                      supervisor: self,
                                      task: @task,
                                      settings: @supervisor_settings,
                                      site_id: site_id,
                                      site_settings: merged_settings,
                                      ip: endpoint['ip'],
                                      port: endpoint['port'],
                                      logger: @logger,
                                      archive: @archive,
                                      collect: @collect
                                    })
        end
      end
    end

    # stop
    def stop
      log "Stopping supervisor #{@supervisor_settings['site_id']}", level: :info

      @accept_task&.cancel if @accept_task&.running?
      @accept_task = nil

      @endpoint = nil
      super
    end

    def build_proxy(settings)
      SiteProxy.new settings
    end

    def self.build_id_from_ip_port(ip, port)
      Digest::MD5.hexdigest("#{ip}:#{port}")[0..8]
    end
  end
end
