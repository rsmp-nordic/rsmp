RSpec.describe 'Connecting' do
  let(:timeout) { 1 }
  let(:ip) { 'localhost' }
  let(:port) { 13_111 }
  let(:site_id) { 'RN+SI0001' }
  let(:site_settings) do
    {
      'site_id' => site_id,
      'supervisors' => [
        { 'ip' => ip, 'port' => port }
      ]
    }
  end
  let(:supervisor_settings) do
    {
      'port' => 13_111,	# use special port to avoid sites connection during test
      'guest' => {
        'sxl' => 'tlc'
      }
    }
  end
  let(:log_settings) do
    {
      'active' => false
    }
  end
  let(:site) do
    RSMP::Site.new(
      site_settings: site_settings,
      log_settings: log_settings
    )
  end
  let(:supervisor) do
    RSMP::Supervisor.new(
      supervisor_settings: supervisor_settings,
      log_settings: log_settings
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
      site_proxy = supervisor.wait_for_site site_id, timeout: timeout
      supervisor_proxy = site.wait_for_supervisor ip, timeout: timeout

      expect(site_proxy).to be_a(RSMP::SiteProxy)
      expect(supervisor_proxy).to be_a(RSMP::SupervisorProxy)

      expect(supervisor.proxies.size).to eq(1)
      expect(site.proxies.size).to eq(1)

      site_proxy.wait_for_state :ready, timeout: timeout
      supervisor_proxy.wait_for_state :ready, timeout: timeout

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
      site_proxy = supervisor.wait_for_site site_id, timeout: timeout
      supervisor_proxy = site.wait_for_supervisor ip, timeout: timeout

      expect(supervisor.proxies.size).to eq(1)
      expect(site.proxies.size).to eq(1)

      expect(site_proxy).to be_a(RSMP::SiteProxy)
      expect(supervisor_proxy).to be_a(RSMP::SupervisorProxy)

      site_proxy.wait_for_state :ready, timeout: timeout
      supervisor_proxy.wait_for_state :ready, timeout: timeout

      expect(site_proxy.state).to eq(:ready)
      expect(supervisor_proxy.state).to eq(:ready)

      task.stop
    end
  end

  it 'establishes connection and stays connected (no reconnection loop)' do
    AsyncRSpec.async context: lambda {
      supervisor.start
      supervisor.ready_condition.wait
      site.start
    } do |task|
      site_proxy = supervisor.wait_for_site site_id, timeout: timeout
      supervisor_proxy = site.wait_for_supervisor ip, timeout: timeout

      site_proxy.wait_for_state :ready, timeout: timeout
      supervisor_proxy.wait_for_state :ready, timeout: timeout

      # Verify connection stays stable
      initial_proxy_count = site.proxies.size
      Async::Task.current.sleep 0.3

      expect(site_proxy.state).to eq(:ready)
      expect(supervisor_proxy.state).to eq(:ready)
      expect(supervisor.proxies.size).to eq(1)
      expect(site.proxies.size).to eq(initial_proxy_count)

      task.stop
    end
  end
end
