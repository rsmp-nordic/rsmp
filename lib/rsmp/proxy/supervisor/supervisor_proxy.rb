# Handles a site connection to a remote supervisor

require 'digest'
require_relative 'connection'
require_relative 'aggregated_status'
require_relative 'alarms'
require_relative 'commands'
require_relative 'status'
require_relative 'subscriptions'
require_relative 'messages'

module RSMP
  class SupervisorProxy < Proxy
    include SupervisorProxyExtensions::Connection
    include SupervisorProxyExtensions::AggregatedStatus
    include SupervisorProxyExtensions::Alarms
    include SupervisorProxyExtensions::Commands
    include SupervisorProxyExtensions::Status
    include SupervisorProxyExtensions::Subscriptions
    include SupervisorProxyExtensions::Messages

    attr_reader :supervisor_id, :site

    def initialize(options)
      super(options.merge(node: options[:site]))
      @site = options[:site]
      @site_settings = @site.site_settings.clone
      @ip = options[:ip]
      @port = options[:port]
      @status_subscriptions = {}
      @sxl = @site_settings['sxl']
      @synthetic_id = Supervisor.build_id_from_ip_port @ip, @port
    end

    def timer(now)
      super
      status_update_timer now if ready?
    end

    def handshake_complete
      sanitized_sxl_version = RSMP::Schema.sanitize_version(sxl_version)
      log "Connection to supervisor established, using core #{@core_version}, #{sxl} #{sanitized_sxl_version}",
          level: :info
      change_state :ready
      start_watchdog
      send_initial_state if @site_settings['send_after_connect']
      super
    end

    def version_accepted(message)
      log "Received Version message, using RSMP #{@core_version}", message: message, level: :log
      start_timer
      acknowledge message
      @version_determined = true
      send_watchdog
    end

    def sxl_version
      @site_settings['sxl_version'].to_s
    end

    def process_version(message)
      return extraneous_version message if @version_determined

      check_core_version message
      check_sxl_version message
      @site_id = Supervisor.build_id_from_ip_port @ip, @port
      version_accepted message
    end

    def check_sxl_version(message); end

    def main
      @site.main
    end
  end
end
