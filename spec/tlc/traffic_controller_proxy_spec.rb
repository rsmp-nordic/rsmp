RSpec.describe RSMP::TLC::TrafficControllerProxy do
  let(:log_settings) { { 'active' => false } }
  let(:supervisor_settings) do
    {
      'port' => 13113,
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
    end
    
    it 'is a subclass of SiteProxy' do
      expect(proxy).to be_a(RSMP::SiteProxy)
    end
  end
  
  describe '#set_plan' do
    let(:plan_nr) { 3 }
    let(:security_code) { '1234' }
    
    context 'when proxy is not ready' do
      it 'raises NotReady error' do
        expect { proxy.set_plan(plan_nr, security_code: security_code) }.to raise_error(RSMP::NotReady)
      end
    end
    
    context 'when main component is not available' do
      before do
        # Mock ready state but no main component
        allow(proxy).to receive(:validate_ready)
        allow(proxy).to receive(:main).and_return(nil)
      end
      
      it 'raises error about missing main component' do
        expect { proxy.set_plan(plan_nr, security_code: security_code) }.to raise_error("TLC main component not found")
      end
    end
    
    context 'with valid inputs' do
      let(:main_component) { double('main_component', c_id: 'TLC001') }
      
      before do
        allow(proxy).to receive(:validate_ready)
        allow(proxy).to receive(:main).and_return(main_component)
        allow(proxy).to receive(:send_command).and_return({ sent: double('message') })
      end
      
      it 'calls send_command with correct parameters' do
        expected_command_list = [
          { "cCI" => "M0002", "cO" => "setPlan", "n" => "status", "v" => "True" },
          { "cCI" => "M0002", "cO" => "setPlan", "n" => "securityCode", "v" => "1234" },
          { "cCI" => "M0002", "cO" => "setPlan", "n" => "timeplan", "v" => "3" }
        ]
        
        expect(proxy).to receive(:send_command).with('TLC001', expected_command_list, {})
        proxy.set_plan(plan_nr, security_code: security_code)
      end
      
      it 'passes through options' do
        options = { collect: true }
        expect(proxy).to receive(:send_command).with(anything, anything, options)
        proxy.set_plan(plan_nr, security_code: security_code, options: options)
      end
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
      let(:main_component) { double('main_component', c_id: 'TLC001') }
      
      before do
        allow(proxy).to receive(:validate_ready)
        allow(proxy).to receive(:main).and_return(main_component)
      end
      
      it 'calls request_status with correct parameters' do
        expected_status_list = [
          { "sCI" => "S0014", "n" => "status" },
          { "sCI" => "S0014", "n" => "source" }
        ]
        
        expect(proxy).to receive(:request_status).with('TLC001', expected_status_list, {}).and_return({ sent: double('message') })
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
        
        expect(proxy.current_plan).to eq(2)
        expect(proxy.plan_source).to eq('forced')
      end
      
      it 'handles partial status response' do
        collector = double('collector')
        status_response = {
          'sS' => [
            { 'n' => 'status', 's' => '1' }
            # missing source
          ]
        }
        
        allow(collector).to receive(:wait).and_return(status_response)
        allow(proxy).to receive(:request_status).and_return({ collector: collector })
        
        proxy.fetch_signal_plan(options: { collect: true })
        
        expect(proxy.current_plan).to eq(1)
        expect(proxy.plan_source).to be_nil
      end
      
      it 'handles malformed status response' do
        collector = double('collector')
        status_response = { 'sS' => nil }
        
        allow(collector).to receive(:wait).and_return(status_response)
        allow(proxy).to receive(:request_status).and_return({ collector: collector })
        
        proxy.fetch_signal_plan(options: { collect: true })
        
        expect(proxy.current_plan).to be_nil
        expect(proxy.plan_source).to be_nil
      end
      
      it 'does not store values when no collector is used' do
        allow(proxy).to receive(:request_status).and_return({ sent: double('message') })
        
        proxy.fetch_signal_plan
        
        expect(proxy.current_plan).to be_nil
        expect(proxy.plan_source).to be_nil
      end
    end
  end
  
  describe 'status value persistence' do
    let(:main_component) { double('main_component', c_id: 'TLC001') }
    
    before do
      allow(proxy).to receive(:validate_ready)
      allow(proxy).to receive(:main).and_return(main_component)
    end
    
    it 'retains status values between calls' do
      collector = double('collector')
      status_response = {
        'sS' => [
          { 'n' => 'status', 's' => '3' },
          { 'n' => 'source', 's' => 'startup' }
        ]
      }
      
      allow(collector).to receive(:wait).and_return(status_response)
      allow(proxy).to receive(:request_status).and_return({ collector: collector })
      
      # First call stores values
      proxy.fetch_signal_plan(options: { collect: true })
      expect(proxy.current_plan).to eq(3)
      expect(proxy.plan_source).to eq('startup')
      
      # Second call without collector doesn't clear values
      allow(proxy).to receive(:request_status).and_return({ sent: double('message') })
      proxy.fetch_signal_plan
      expect(proxy.current_plan).to eq(3)
      expect(proxy.plan_source).to eq('startup')
    end
    
    it 'updates status values with new response' do
      collector1 = double('collector1')
      status_response1 = {
        'sS' => [
          { 'n' => 'status', 's' => '1' },
          { 'n' => 'source', 's' => 'forced' }
        ]
      }
      
      collector2 = double('collector2')
      status_response2 = {
        'sS' => [
          { 'n' => 'status', 's' => '2' },
          { 'n' => 'source', 's' => 'startup' }
        ]
      }
      
      allow(collector1).to receive(:wait).and_return(status_response1)
      allow(collector2).to receive(:wait).and_return(status_response2)
      
      # First call
      allow(proxy).to receive(:request_status).and_return({ collector: collector1 })
      proxy.fetch_signal_plan(options: { collect: true })
      expect(proxy.current_plan).to eq(1)
      expect(proxy.plan_source).to eq('forced')
      
      # Second call updates values
      allow(proxy).to receive(:request_status).and_return({ collector: collector2 })
      proxy.fetch_signal_plan(options: { collect: true })
      expect(proxy.current_plan).to eq(2)
      expect(proxy.plan_source).to eq('startup')
    end
  end
end