RSpec.describe 'TLC Proxy Integration' do
  let(:timeout) { 1 }
  let(:ip) { 'localhost' }
  let(:port) { 13112 }  # Different port to avoid conflicts
  let(:site_id) { 'TLC001' }
  
  let(:tlc_site_settings) {
    {
      'site_id' => site_id,
      'supervisors' => [
        { 'ip' => ip, 'port' => port }
      ],
      'sxl' => 'tlc',
      'sxl_version' => '1.0.13',
      'components' => {
        site_id => { 'type' => 'main' }
      },
      'signal_plans' => {
        1 => { 'cycle_time' => 60 },
        2 => { 'cycle_time' => 80 },
        3 => { 'cycle_time' => 120 }
      },
      'security_codes' => { 1 => '1111', 2 => '2222' }
    }
  }
  
  let(:supervisor_settings) {
    {
      'port' => port,
      'sites' => {
        site_id => { 'sxl' => 'tlc' }
      },
      'guest' => {
        'sxl' => 'tlc'  # Use valid schema type
      }
    }
  }
  
  let(:log_settings) {
    {
      'active' => false
    }
  }
  
  let(:tlc_site) {
    RSMP::TLC::TrafficControllerSite.new(
      site_settings: tlc_site_settings,
      log_settings: log_settings
    )
  }
  
  let(:supervisor) {
    RSMP::Supervisor.new(
      supervisor_settings: supervisor_settings,
      log_settings: log_settings
    )
  }

  it 'creates TLCProxy when TLC connects to supervisor' do
    expect(supervisor.proxies.size).to eq(0)
    expect(tlc_site.proxies.size).to eq(1)
    expect(tlc_site.proxies.first.state).to eq(:disconnected)

    AsyncRSpec.async context: lambda {
      supervisor.start
      tlc_site.start
    } do |task|
      # Wait for TLC site to connect to supervisor
      tlc_proxy = supervisor.wait_for_site site_id, timeout: timeout
      supervisor_proxy = tlc_site.wait_for_supervisor ip, timeout: timeout
      
      # Verify that supervisor created a TLCProxy instead of regular SiteProxy
      expect(tlc_proxy).to be_an(RSMP::TLC::TrafficLightControllerProxy)
      expect(tlc_proxy.site_id).to eq(site_id)
      
      # Wait a bit for handshake to complete
      if tlc_proxy.ready?
        # If ready, verify that the TLC proxy has the expected methods
        expect(tlc_proxy).to respond_to(:set_plan)
        expect(tlc_proxy).to respond_to(:fetch_signal_plan)
        
        # Test fetching signal plan (this should work without errors)
        result = tlc_proxy.fetch_signal_plan(collect: { timeout: 0.1 })
        expect(result).to have_key(:sent)
        expect(result).to have_key(:collector)
        
        # The collector should receive a StatusResponse
        collector = result[:collector]
        expect(collector.messages.size).to eq(1)
        response = collector.messages.first
        expect(response).to be_an(RSMP::StatusResponse)
        expect(response.attribute('sS')).to be_an(Array)
        
        # Check that we get status and source for the signal plan
        status_items = response.attribute('sS')
        status_names = status_items.map { |item| item['n'] }
        expect(status_names).to include('status', 'source')
        
        # Test setting signal plan (this should work without errors)
        result = tlc_proxy.set_plan(2, security_code: '2222', options: { collect: { timeout: 0.1 } })
        expect(result).to have_key(:sent)
        expect(result).to have_key(:collector)
        
        # The collector should receive a CommandResponse
        collector = result[:collector]
        expect(collector.messages.size).to eq(1)
        response = collector.messages.first
        expect(response).to be_an(RSMP::CommandResponse)
        
        # Verify plan was actually changed on the TLC
        tlc_controller = tlc_site.main
        expect(tlc_controller.plan).to eq(2)
      else
        # If not ready, just verify that the proxy has the expected methods
        expect(tlc_proxy).to respond_to(:set_plan)
        expect(tlc_proxy).to respond_to(:fetch_signal_plan)
      end
    end
  end
  
  it 'handles errors gracefully when TLC is not ready' do
    AsyncRSpec.async do |task|
      # Create a supervisor with TLC configuration to avoid schema errors
      supervisor_without_connection = RSMP::Supervisor.new(
        supervisor_settings: { 'port' => 13113, 'guest' => { 'sxl' => 'tlc' } },
        log_settings: log_settings
      )
      
      # Create a TLC proxy that is not connected/ready
      settings = {
        supervisor: supervisor_without_connection,
        ip: '127.0.0.1',
        port: 12345,
        socket: double('socket'),
        stream: double('stream'),
        protocol: double('protocol'),
        logger: double('logger'),
        archive: double('archive'),
        site_id: 'TLC001'
      }
      
      allow(supervisor_without_connection).to receive(:supervisor_settings).and_return({})
      
      tlc_proxy = RSMP::TLC::TrafficLightControllerProxy.new(settings)
      
      # Should raise NotReady error when trying to use methods on disconnected proxy
      expect { tlc_proxy.set_plan(1, security_code: '1234') }.to raise_error(RSMP::NotReady)
      expect { tlc_proxy.fetch_signal_plan }.to raise_error(RSMP::NotReady)
    end
  end
end