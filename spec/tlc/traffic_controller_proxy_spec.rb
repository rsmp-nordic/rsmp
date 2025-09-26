RSpec.describe RSMP::TLC::TrafficControllerProxy do
  let(:log_settings) { { 'active' => false } }
  let(:supervisor_settings) do
    {
      'port' => 13113,
      'proxy_type' => 'auto',  # Enable auto-detection for tests
      'guest' => {
        'timeouts' => {
          'watchdog' => 0.2,
          'acknowledgement' => 0.2,
          'command_timeout' => 5.0
        }
      },
      'sites' => {
        'TLC001' => { 'sxl' => 'tlc', 'type' => 'tlc' }
      }
    }
  end
  
  let(:supervisor) do
    RSMP::Supervisor.new(
      supervisor_settings: supervisor_settings,
      log_settings: log_settings
    )
  end
  
  let(:options) do
    {
      supervisor: supervisor,
      ip: '127.0.0.1',
      port: 12345,
      site_id: 'TLC001'
    }
  end
  
  let(:proxy) { described_class.new(options) }
  
  describe '#initialize' do
    it 'initializes with nil status values' do
      expect(proxy.current_plan).to be_nil
      expect(proxy.plan_source).to be_nil
      expect(proxy.timeplan).to be_nil
    end
    
    it 'retrieves timeouts from supervisor settings' do
      expected_timeouts = {
        'watchdog' => 0.2,
        'acknowledgement' => 0.2,
        'command_timeout' => 5.0
      }
      expect(proxy.timeouts).to eq(expected_timeouts)
    end
    
    it 'is a subclass of SiteProxy' do
      expect(proxy).to be_a(RSMP::SiteProxy)
    end
  end
  
  describe 'status value storage' do
    let(:main_component) { RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true) }
    
    before do
      proxy.instance_variable_set(:@main, main_component)
    end
    
    it 'updates timeplan and plan_source when processing S0014 status updates' do
      # Set proxy to connected state so acknowledge can be sent
      proxy.instance_variable_set(:@state, :connected)
      
      status_update = RSMP::StatusUpdate.new({
        'mId' => 'abc123',
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [
          { 'sCI' => 'S0014', 'n' => 'status', 's' => '3', 'q' => 'recent' },
          { 'sCI' => 'S0014', 'n' => 'source', 's' => 'forced', 'q' => 'recent' }
        ]
      })
      
      proxy.process_status_update(status_update)
      
      expect(proxy.timeplan).to eq(3)
      expect(proxy.current_plan).to eq(3)
      expect(proxy.plan_source).to eq('forced')
    end
    
    it 'returns timeplan attributes from main component' do
      statuses = { 'S0014' => { 'status' => { 's' => '2', 'q' => 'recent' } } }
      main_component.instance_variable_set(:@statuses, statuses)
      
      expect(proxy.timeplan_attributes).to eq({ 'status' => { 's' => '2', 'q' => 'recent' } })
    end
    
    it 'returns empty hash when no main component' do
      proxy.instance_variable_set(:@main, nil)
      expect(proxy.timeplan_attributes).to eq({})
    end
  end
  
  describe 'method functionality' do
    let(:main_component) { RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true) }
    
    before do
      proxy.instance_variable_set(:@main, main_component)
    end
    
    it 'validates proxy is ready before set_timeplan' do
      expect { proxy.set_timeplan(3, security_code: '1234') }.to raise_error(RSMP::NotReady)
    end
    
    it 'validates proxy is ready before fetch_signal_plan' do
      expect { proxy.fetch_signal_plan }.to raise_error(RSMP::NotReady)
    end
    
    it 'validates proxy is ready before subscribe_to_timeplan' do
      expect { proxy.subscribe_to_timeplan }.to raise_error(RSMP::NotReady)
    end
    
    it 'raises error when main component is missing for set_timeplan' do
      proxy.instance_variable_set(:@main, nil)
      proxy.instance_variable_set(:@state, :ready)
      
      expect { proxy.set_timeplan(3, security_code: '1234') }.to raise_error("TLC main component not found")
    end
  end
end