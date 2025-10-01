# RSMP supervisor (server)
# The supervisor waits for sites to connect.
# Connections to sites are handles via site proxies.

require_relative 'settings'
require_relative 'connections'
require_relative 'site_management'

module RSMP
  class Supervisor < Node
    include SupervisorExtensions::Settings
    include SupervisorExtensions::Connections
    include SupervisorExtensions::SiteManagement

    attr_reader :core_version, :supervisor_settings, :proxies, :logger, :ready_condition

    attr_accessor :site_id_condition

    def initialize(options = {})
      handle_supervisor_settings(options[:supervisor_settings] || {})
      super
      @proxies = []
      @ready_condition = Async::Notification.new
      @site_id_condition = Async::Notification.new
    end

    def self.build_id_from_ip_port(ip, port)
      Digest::MD5.hexdigest("#{ip}:#{port}")[0..8]
    end
  end
end
