RSpec.describe 'Connecting' do
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
        'guest' => { 'sxl' => 'tlc' }
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
    expect(supervisor.proxies.size).to eq(0)
    expect(site.proxies.size).to eq(1)
    expect(site.proxies.first.state).to eq(:disconnected)

    AsyncRSpec.async context: lambda {
      supervisor.start
      supervisor.ready_condition.wait
      site.start
    } do |task|
      site_proxy = supervisor.wait_for_site config[:site_id], timeout: config[:timeout]
      supervisor_proxy = site.wait_for_supervisor config[:ip], timeout: config[:timeout]

      expect(site_proxy).to be_a(RSMP::SiteProxy)
      expect(supervisor_proxy).to be_a(RSMP::SupervisorProxy)

      expect(supervisor.proxies.size).to eq(1)
      expect(site.proxies.size).to eq(1)

      site_proxy.wait_for_state :ready, timeout: config[:timeout]
      supervisor_proxy.wait_for_state :ready, timeout: config[:timeout]

      expect(site_proxy.state).to eq(:ready)
      expect(supervisor_proxy.state).to eq(:ready)

      task.stop
    end
  end

  it 'works when the site is started first' do
    expect(supervisor.proxies.size).to eq(0)
    expect(site.proxies.size).to eq(1)
    expect(site.proxies.first.state).to eq(:disconnected)

    AsyncRSpec.async context: lambda {
      site.start
      supervisor.start
      supervisor.ready_condition.wait
    } do |task|
      site_proxy = supervisor.wait_for_site config[:site_id], timeout: config[:timeout]
      supervisor_proxy = site.wait_for_supervisor config[:ip], timeout: config[:timeout]

      expect(supervisor.proxies.size).to eq(1)
      expect(site.proxies.size).to eq(1)

      expect(site_proxy).to be_a(RSMP::SiteProxy)
      expect(supervisor_proxy).to be_a(RSMP::SupervisorProxy)

      site_proxy.wait_for_state :ready, timeout: config[:timeout]
      supervisor_proxy.wait_for_state :ready, timeout: config[:timeout]

      expect(site_proxy.state).to eq(:ready)
      expect(supervisor_proxy.state).to eq(:ready)

      task.stop
    end
  end
end
