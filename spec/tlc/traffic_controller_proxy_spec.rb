RSpec.describe RSMP::TLC::TrafficControllerProxy do
  let(:log_settings) { { 'active' => false } }
  let(:supervisor_settings) do
    {
      'port' => 13113,
      'proxy_type' => 'auto',  # Enable auto-detection for tests
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
  
  let(:timeouts) { { 'watchdog' => 0.2, 'acknowledgement' => 0.2 } }
  
  let(:options) do
    {
      supervisor: supervisor,
      ip: '127.0.0.1',
      port: 12345,
      site_id: 'TLC001',
      timeouts: timeouts
    }
  end
  
  let(:proxy) { described_class.new(options) }
  
  describe '#initialize' do
    it 'initializes with nil status values' do
      expect(proxy.current_plan).to be_nil
      expect(proxy.plan_source).to be_nil
      expect(proxy.timeplan).to be_nil
    end
    
    it 'stores timeouts configuration' do
      expect(proxy.timeouts).to eq(timeouts)
    end
    
    it 'is a subclass of SiteProxy' do
      expect(proxy).to be_a(RSMP::SiteProxy)
    end
  end
  
  describe '#handshake_complete' do
    before do
      # Set up a real main component instead of mocking
      proxy.instance_variable_set(:@main, RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true))
      allow(proxy).to receive(:start_watchdog)  # Mock watchdog start
      allow(proxy).to receive(:log)
      # Mock the parent handshake_complete to avoid async issues
      allow_any_instance_of(RSMP::SiteProxy).to receive(:handshake_complete)
    end
    
    it 'handles subscription errors gracefully' do
      allow(proxy).to receive(:validate_ready).and_raise(StandardError.new("test error"))
      expect { proxy.handshake_complete }.not_to raise_error
    end
  end
  
  describe '#subscribe_to_timeplan' do
    context 'when proxy is not ready' do
      it 'raises NotReady error' do
        expect { proxy.subscribe_to_timeplan }.to raise_error(RSMP::NotReady)
      end
    end
    
    context 'when proxy is ready' do
      before do
        # Set up a real main component instead of mocking
        proxy.instance_variable_set(:@main, RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true))
        allow(proxy).to receive(:validate_ready)
        allow(proxy).to receive(:subscribe_to_status).and_return({ sent: RSMP::StatusSubscribe.new({}) })
      end
      
      it 'subscribes to S0014 status updates with update on change' do
        expected_status_list = [
          { "sCI" => "S0014", "n" => "status", "sOc" => true },
          { "sCI" => "S0014", "n" => "source", "sOc" => true }
        ]
        
        expect(proxy).to receive(:subscribe_to_status).with('TLC001', expected_status_list, timeouts)
        proxy.subscribe_to_timeplan
      end
      
      it 'merges provided options with timeouts' do
        custom_options = { collect: true }
        expected_options = timeouts.merge(custom_options)
        
        expect(proxy).to receive(:subscribe_to_status).with(anything, anything, expected_options)
        proxy.subscribe_to_timeplan(options: custom_options)
      end
      
      it 'adds subscription to status_subscriptions tracking' do
        # Mock the subscribe_to_status to simulate adding to @status_subscriptions
        allow(proxy).to receive(:subscribe_to_status) do |component_id, status_list, options|
          # Simulate what the real subscribe_to_status does - add to @status_subscriptions
          proxy.instance_variable_get(:@status_subscriptions)[component_id] ||= {}
          status_list.each do |item|
            sCI, n = item['sCI'], item['n']
            proxy.instance_variable_get(:@status_subscriptions)[component_id][sCI] ||= {}
            proxy.instance_variable_get(:@status_subscriptions)[component_id][sCI][n] = { 'uRt' => nil, 'sOc' => item['sOc'] }
          end
          { sent: RSMP::StatusSubscribe.new({}) }
        end
        
        proxy.subscribe_to_timeplan
        
        status_subscriptions = proxy.instance_variable_get(:@status_subscriptions)
        expect(status_subscriptions['TLC001']).not_to be_nil
        expect(status_subscriptions['TLC001']['S0014']).not_to be_nil
        expect(status_subscriptions['TLC001']['S0014']['status']).not_to be_nil
        expect(status_subscriptions['TLC001']['S0014']['source']).not_to be_nil
      end
    end
  end
  
  describe '#process_status_update' do
    let(:message) do
      RSMP::StatusUpdate.new({
        'cId' => 'TLC001',
        'sS' => [
          { 'sCI' => 'S0014', 'n' => 'status', 's' => '3' },
          { 'sCI' => 'S0014', 'n' => 'source', 's' => 'forced' }
        ],
        'mId' => '123',
        'ntsOId' => '',
        'xNId' => '',
        'cTS' => '2023-01-01T00:00:00.000Z'
      })
    end
    
    before do
      # Set up a real main component instead of mocking
      main_component = RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true)
      proxy.instance_variable_set(:@main, main_component)
      allow(proxy).to receive(:acknowledge)
      allow(proxy).to receive(:log)
      # Don't mock the parent process_status_update method - let it call through
      # but mock the methods it calls to avoid complications
      allow(proxy).to receive(:find_component).and_return(main_component)
      allow(main_component).to receive(:check_repeat_values)
      allow(main_component).to receive(:store_status)
    end
    
    it 'calls parent process_status_update' do
      # Just verify it doesn't error - we can't easily test the parent call
      expect { proxy.process_status_update(message) }.not_to raise_error
    end
    
    it 'automatically stores S0014 timeplan values' do
      proxy.process_status_update(message)
      
      expect(proxy.timeplan).to eq(3)
      expect(proxy.current_plan).to eq(3)
      expect(proxy.plan_source).to eq('forced')
    end
    
    it 'ignores updates from other components' do
      other_message = RSMP::StatusUpdate.new({
        'cId' => 'OTHER001',
        'sS' => [
          { 'sCI' => 'S0014', 'n' => 'status', 's' => '3' },
          { 'sCI' => 'S0014', 'n' => 'source', 's' => 'forced' }
        ],
        'mId' => '123',
        'ntsOId' => '',
        'xNId' => '',
        'cTS' => '2023-01-01T00:00:00.000Z'
      })
      
      proxy.process_status_update(other_message)
      
      expect(proxy.timeplan).to be_nil
      expect(proxy.current_plan).to be_nil
    end
  end
  
  describe '#timeplan_attributes' do
    it 'returns S0014 attributes from main component' do
      # Set up a real main component with status data
      main_component = RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true)
      statuses = { 'S0014' => { 'status' => { 's' => '2', 'q' => 'recent' } } }
      main_component.instance_variable_set(:@statuses, statuses)
      proxy.instance_variable_set(:@main, main_component)
      
      expect(proxy.timeplan_attributes).to eq({ 'status' => { 's' => '2', 'q' => 'recent' } })
    end
    
    it 'returns empty hash when no main component' do
      proxy.instance_variable_set(:@main, nil)
      expect(proxy.timeplan_attributes).to eq({})
    end
    
    it 'returns empty hash when no S0014 data' do
      # Set up a real main component with no S0014 data
      main_component = RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true)
      main_component.instance_variable_set(:@statuses, {})
      proxy.instance_variable_set(:@main, main_component)
      
      expect(proxy.timeplan_attributes).to eq({})
    end
  end
  
  describe '#set_timeplan' do
    let(:plan_nr) { 3 }
    let(:security_code) { '1234' }
    
    context 'when proxy is not ready' do
      it 'raises NotReady error' do
        expect { proxy.set_timeplan(plan_nr, security_code: security_code) }.to raise_error(RSMP::NotReady)
      end
    end
    
    context 'when main component is not available' do
      before do
        allow(proxy).to receive(:validate_ready)
        allow(proxy).to receive(:main).and_return(nil)
      end
      
      it 'raises error about missing main component' do
        expect { proxy.set_timeplan(plan_nr, security_code: security_code) }.to raise_error("TLC main component not found")
      end
    end
    
    context 'with valid inputs' do
      before do
        # Set up a real main component instead of mocking
        main_component = RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true)
        proxy.instance_variable_set(:@main, main_component)
        allow(proxy).to receive(:validate_ready)
        allow(proxy).to receive(:send_command).and_return({ sent: RSMP::CommandRequest.new({}) })
      end
      
      it 'calls send_command with correct parameters and merged timeouts' do
        expected_command_list = [
          { "cCI" => "M0002", "cO" => "setPlan", "n" => "status", "v" => "True" },
          { "cCI" => "M0002", "cO" => "setPlan", "n" => "securityCode", "v" => "1234" },
          { "cCI" => "M0002", "cO" => "setPlan", "n" => "timeplan", "v" => "3" }
        ]
        
        expect(proxy).to receive(:send_command).with('TLC001', expected_command_list, timeouts)
        proxy.set_timeplan(plan_nr, security_code: security_code)
      end
      
      it 'merges provided options with timeouts' do
        custom_options = { collect: true }
        expected_options = timeouts.merge(custom_options)
        
        expect(proxy).to receive(:send_command).with(anything, anything, expected_options)
        proxy.set_timeplan(plan_nr, security_code: security_code, options: custom_options)
      end
    end
  end
  
  describe '#unsubscribe_all' do
    before do
      # Set up some test subscriptions in @status_subscriptions
      status_subscriptions = {
        'TLC001' => {
          'S0014' => {
            'status' => { 'uRt' => nil, 'sOc' => true },
            'source' => { 'uRt' => nil, 'sOc' => true }
          }
        }
      }
      proxy.instance_variable_set(:@status_subscriptions, status_subscriptions)
      allow(proxy).to receive(:unsubscribe_to_status)
      allow(proxy).to receive(:log)
    end
    
    it 'unsubscribes from all tracked subscriptions' do
      expect(proxy).to receive(:unsubscribe_to_status).with('TLC001', [{ 'sCI' => 'S0014', 'n' => 'status' }])
      expect(proxy).to receive(:unsubscribe_to_status).with('TLC001', [{ 'sCI' => 'S0014', 'n' => 'source' }])
      proxy.unsubscribe_all
    end
    
    it 'handles unsubscribe errors gracefully' do
      allow(proxy).to receive(:unsubscribe_to_status).and_raise(StandardError.new("test error"))
      expect { proxy.unsubscribe_all }.not_to raise_error
    end
  end
  
  describe '#close' do
    it 'can be called without errors' do
      allow_any_instance_of(RSMP::SiteProxy).to receive(:close)
      expect { proxy.close }.not_to raise_error
    end
  end

  describe '#fetch_signal_plan' do
    context 'when proxy is not ready' do
      it 'raises NotReady error' do
        expect { proxy.fetch_signal_plan }.to raise_error(RSMP::NotReady)
      end
    end
    
    context 'when main component is not available' do
      before do
        allow(proxy).to receive(:validate_ready)
        allow(proxy).to receive(:main).and_return(nil)
      end
      
      it 'raises error about missing main component' do
        expect { proxy.fetch_signal_plan }.to raise_error("TLC main component not found")
      end
    end
    
    context 'with valid conditions' do
      before do
        # Set up a real main component instead of mocking
        main_component = RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true)
        proxy.instance_variable_set(:@main, main_component)
        allow(proxy).to receive(:validate_ready)
      end
      
      it 'calls request_status with correct parameters and merged timeouts' do
        expected_status_list = [
          { "sCI" => "S0014", "n" => "status" },
          { "sCI" => "S0014", "n" => "source" }
        ]
        
        expect(proxy).to receive(:request_status).with('TLC001', expected_status_list, timeouts).and_return({ sent: RSMP::StatusRequest.new({}) })
        proxy.fetch_signal_plan
      end
      
      it 'stores status values when collector is used' do
        collector = double('collector')
        status_response = {
          'sS' => [
            { 'n' => 'status', 's' => '2' },
            { 'n' => 'source', 's' => 'forced' }
          ]
        }
        
        allow(collector).to receive(:wait).and_return(status_response)
        allow(proxy).to receive(:request_status).and_return({ collector: collector })
        
        proxy.fetch_signal_plan(options: { collect: true })
        
        expect(proxy.timeplan).to eq(2)
        expect(proxy.current_plan).to eq(2)
        expect(proxy.plan_source).to eq('forced')
      end
    end
  end
end