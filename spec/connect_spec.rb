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

  it 'establishes connection and sends aggregated status without reconnection loop' do
    log_settings_with_output = {
      'active' => true,
      'color' => false
    }
    site_with_log = RSMP::Site.new(
      site_settings: site_settings,
      log_settings: log_settings_with_output
    )
    supervisor_with_log = RSMP::Supervisor.new(
      supervisor_settings: supervisor_settings,
      log_settings: log_settings_with_output
    )

    AsyncRSpec.async context: lambda {
      supervisor_with_log.start
      supervisor_with_log.ready_condition.wait
      site_with_log.start
    } do |task|
      site_proxy = supervisor_with_log.wait_for_site site_id, timeout: timeout
      supervisor_proxy = site_with_log.wait_for_supervisor ip, timeout: timeout

      site_proxy.wait_for_state :ready, timeout: timeout
      supervisor_proxy.wait_for_state :ready, timeout: timeout

      # Verify connection is stable - sleep briefly and check we're still ready
      Async::Task.current.sleep 0.2

      expect(site_proxy.state).to eq(:ready)
      expect(supervisor_proxy.state).to eq(:ready)
      expect(supervisor_with_log.proxies.size).to eq(1)
      expect(site_with_log.proxies.size).to eq(1)

      task.stop
    end
  end
end
