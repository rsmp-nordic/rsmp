require_relative '../support/async_helper'

describe 'Connecting' do
  let(:config) do
    {
      timeout: 1,
      ip: 'localhost',
      port: 13_111,
      site_id: 'RN+SI0001',
      site_settings: {
        'site_id' => 'RN+SI0001',
        'supervisors' => [
          { 'ip' => 'localhost', 'port' => 13_111 }
        ]
      },
      supervisor_settings: {
        'port' => 13_111,
        'default' => { 'sxls' => { 'tlc' => RSMP::Schema.latest_version(:tlc) } }
      },
      log_settings: { 'active' => false }
    }
  end

  let(:site) do
    RSMP::Site.new(
      site_settings: config[:site_settings],
      log_settings: config[:log_settings]
    )
  end

  let(:supervisor) do
    RSMP::Supervisor.new(
      supervisor_settings: config[:supervisor_settings],
      log_settings: config[:log_settings]
    )
  end

  it 'works when the supervisor is started first' do
    expect(supervisor.proxies.size).to be == 0
    expect(site.proxies.size).to be == 1
    expect(site.proxies.first.state).to be == :disconnected

    with_async_context(context: lambda {
      supervisor.start
      supervisor.ready_condition.wait
      site.start
    }) do |_task|
      site_proxy = supervisor.wait_for_site config[:site_id], timeout: config[:timeout]
      supervisor_proxy = site.wait_for_supervisor config[:ip], timeout: config[:timeout]

      expect(site_proxy).to be_a(RSMP::SiteProxy)
      expect(supervisor_proxy).to be_a(RSMP::SupervisorProxy)

      expect(supervisor.proxies.size).to be == 1
      expect(site.proxies.size).to be == 1

      site_proxy.wait_for_state :ready, timeout: config[:timeout]
      supervisor_proxy.wait_for_state :ready, timeout: config[:timeout]

      expect(site_proxy.state).to be == :ready
      expect(supervisor_proxy.state).to be == :ready
    end
  end

  it 'works when the site is started first' do
    expect(supervisor.proxies.size).to be == 0
    expect(site.proxies.size).to be == 1
    expect(site.proxies.first.state).to be == :disconnected

    with_async_context(context: lambda {
      site.start
      supervisor.start
      supervisor.ready_condition.wait
    }) do |_task|
      site_proxy = supervisor.wait_for_site config[:site_id], timeout: config[:timeout]
      supervisor_proxy = site.wait_for_supervisor config[:ip], timeout: config[:timeout]

      expect(supervisor.proxies.size).to be == 1
      expect(site.proxies.size).to be == 1

      expect(site_proxy).to be_a(RSMP::SiteProxy)
      expect(supervisor_proxy).to be_a(RSMP::SupervisorProxy)

      site_proxy.wait_for_state :ready, timeout: config[:timeout]
      supervisor_proxy.wait_for_state :ready, timeout: config[:timeout]

      expect(site_proxy.state).to be == :ready
      expect(supervisor_proxy.state).to be == :ready
    end
  end

  it 'works with a core-only 3.3.0 connection' do
    config[:site_settings]['core_version'] = '3.3.0'
    config[:site_settings]['sxls'] = {}
    config[:supervisor_settings]['default']['core_version'] = '3.3.0'
    config[:supervisor_settings]['default']['sxls'] = {}

    with_async_context(context: lambda {
      supervisor.start
      supervisor.ready_condition.wait
      site.start
    }) do |_task|
      site_proxy = supervisor.wait_for_site config[:site_id], timeout: config[:timeout]
      supervisor_proxy = site.wait_for_supervisor config[:ip], timeout: config[:timeout]

      site_proxy.wait_for_state :ready, timeout: config[:timeout]
      supervisor_proxy.wait_for_state :ready, timeout: config[:timeout]

      expect(site_proxy.accepted_sxls).to be == []
      expect(supervisor_proxy.accepted_sxls).to be == []
      expect(site_proxy.schemas).to be == { core: '3.3.0' }
      expect(supervisor_proxy.schemas).to be == { core: '3.3.0' }
    end
  end

  it 'stores receiveAlarms false from a 3.3.0 Version response' do
    config[:site_settings]['core_version'] = '3.3.0'
    config[:supervisor_settings]['default']['core_version'] = '3.3.0'
    config[:supervisor_settings]['default']['receive_alarms'] = false

    with_async_context(context: lambda {
      supervisor.start
      supervisor.ready_condition.wait
      site.start
    }) do |_task|
      supervisor_proxy = site.wait_for_supervisor config[:ip], timeout: config[:timeout]
      supervisor_proxy.wait_for_state :ready, timeout: config[:timeout]

      expect(supervisor_proxy.receive_alarms?).to be == false
    end
  end
end
