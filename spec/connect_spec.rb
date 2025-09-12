RSpec.describe 'Connecting' do
	let(:timeout) { 1 }
	let(:ip) { 'localhost' }
	let(:port) { 13111 }
	let(:site_id) { 'RN+SI0001' }
	let(:site_settings) {
		{
			'site_id' => site_id,
			'supervisors' => [
				{ 'ip' => ip, 'port' => port }
			]
		}
	}
	let(:supervisor_settings) {
		{
			'port' => 13111,		# use special port to avoid sites connection during test
			'guest' => {
				'sxl' => 'tlc'
			}
		}
	}
	let(:log_settings) {
		{
			'active' => false
		}
	}
	let(:site) {
		RSMP::Site.new(
			site_settings: site_settings,
			log_settings: log_settings
		)
	}
	let(:supervisor) {
		RSMP::Supervisor.new(
			supervisor_settings: supervisor_settings,
			log_settings: log_settings
		)
	}

	it 'works when the supervisor is started first' do
		expect(supervisor.proxies.size).to eq(0)
		expect(site.proxies.size).to eq(1)
		expect(site.proxies.first.state).to eq(:disconnected)

    AsyncRSpec.async context: lambda {
			supervisor.start
			sleep(0.1)
			site.start
    } do |task|
			supervisor.ready_condition.wait
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
			sleep(0.1)
			supervisor.start
    } do |task|
			supervisor.ready_condition.wait
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

end
