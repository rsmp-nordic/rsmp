require 'rsmp'

# In-memory protocol and proxy fixtures shared by protocol tests.
module ProxyHelper
  class CapturingProtocol
    attr_reader :lines, :messages

    def initialize(&on_write)
      @lines = []
      @messages = []
      @on_write = on_write
    end

    def write_lines(line)
      @lines << line
      @messages << JSON.parse(line)
      @on_write&.call(line)
    end
  end

  def build_site(core_version:, **settings)
    RSMP::Site.new(
      site_settings: { 'core_version' => core_version, 'supervisors' => [] }.merge(settings),
      log_settings: { 'active' => false }
    )
  end

  def configure_proxy(proxy, core_version:, state: :ready, protocol: CapturingProtocol.new, **attributes)
    { core_version: core_version, state: state, protocol: protocol,
      version_determined: true }.merge(attributes).each do |key, value|
      proxy.instance_variable_set(:"@#{key}", value)
    end
    proxy
  end

  def build_supervisor_proxy(site, core_version:, port: 12_345, **)
    proxy = RSMP::SupervisorProxy.new(site: site, ip: '127.0.0.1', port: port)
    configure_proxy(proxy, core_version: core_version, **)
  end

  def build_site_proxy(core_version:, settings: {}, **)
    supervisor = RSMP::Supervisor.new(supervisor_settings: { 'default' => settings },
                                      log_settings: { 'active' => false })
    proxy = RSMP::SiteProxy.new(supervisor: supervisor, ip: '127.0.0.1', port: 12_345, site_id: 'TLC001')
    configure_proxy(proxy, core_version: core_version, **)
  end

  def messages(proxy)
    proxy.instance_variable_get(:@protocol).messages
  end
end
