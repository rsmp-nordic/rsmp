# RSMP supervisor (server)
# The supervisor waits for sites to connect.
# Connections to sites are handles via site proxies.

module RSMP
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

    # listen for connections
    def run
      log "Starting supervisor on port #{@supervisor_settings['port']}",
          level: :info,
          timestamp: @clock.now

      @endpoint = IO::Endpoint.tcp('0.0.0.0', @supervisor_settings['port'])
      @accept_task = Async::Task.current.async do |task|
        task.annotate 'supervisor accept loop'
        @endpoint.accept do |socket| # creates fibers
          handle_connection(socket)
        rescue StandardError => e
          distribute_error e, level: :internal
        end
      rescue Async::Stop
        # Expected during shutdown - no action needed
      rescue StandardError => e
        distribute_error e, level: :internal
      end

      @ready_condition.signal
      @accept_task.wait
    rescue StandardError => e
      distribute_error e, level: :internal
    end

    # stop
    def stop
      log "Stopping supervisor #{@supervisor_settings['site_id']}", level: :info

      @accept_task&.stop
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
