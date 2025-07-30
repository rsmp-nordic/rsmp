RSpec.describe RSMP::TLC::TrafficControllerProxy do
  let(:supervisor) { double('supervisor') }
  let(:socket) { double('socket') }
  let(:stream) { double('stream') }
  let(:protocol) { double('protocol') }
  let(:logger) { double('logger') }
  let(:archive) { double('archive') }
  
  let(:options) do
    {
      supervisor: supervisor,
      ip: '127.0.0.1',
      port: 12345,
      task: double('task'),
      socket: socket,
      stream: stream,
      protocol: protocol,
      logger: logger,
      archive: archive,
      site_id: 'TLC001'
    }
  end
  
  let(:proxy) { described_class.new(options) }
  
  # Mock the main component
  let(:main_component) do
    double('main_component', c_id: 'TLC001', grouped: true)
  end
  
  before do
    allow(supervisor).to receive(:supervisor_settings).and_return({})
    allow(logger).to receive(:mute)
    allow(logger).to receive(:unmute)
    allow(logger).to receive(:log)
    allow(archive).to receive(:log)
    
    # Mock the components collection to include a main component
    allow(proxy).to receive(:find_component).and_return(main_component)
    proxy.instance_variable_set(:@components, { 'TLC001' => main_component })
  end
  
  describe '#set_plan' do
    let(:plan_nr) { 3 }
    let(:security_code) { '1234' }
    let(:expected_command_list) do
      [
        {
          "cCI" => "M0002",
          "cO" => "setPlan",
          "n" => "status",
          "v" => "True"
        },
        {
          "cCI" => "M0002", 
          "cO" => "setPlan",
          "n" => "securityCode",
          "v" => "1234"
        },
        {
          "cCI" => "M0002",
          "cO" => "setPlan", 
          "n" => "timeplan",
          "v" => "3"
        }
      ]
    end
    
    context 'when proxy is ready' do
      before do
        allow(proxy).to receive(:validate_ready)
        allow(proxy).to receive(:send_command).and_return({ sent: double('message') })
      end
      
      it 'sends M0002 command with correct parameters' do
        expect(proxy).to receive(:send_command).with('TLC001', expected_command_list, {})
        
        proxy.set_plan(plan_nr, security_code: security_code)
      end
      
      it 'accepts options parameter' do
        options = { collect: true }
        expect(proxy).to receive(:send_command).with('TLC001', expected_command_list, options)
        
        proxy.set_plan(plan_nr, security_code: security_code, options: options)
      end
      
      it 'converts plan number to string' do
        expect(proxy).to receive(:send_command) do |component_id, command_list, opts|
          timeplan_command = command_list.find { |cmd| cmd["n"] == "timeplan" }
          expect(timeplan_command["v"]).to eq("3")
        end
        
        proxy.set_plan(plan_nr, security_code: security_code)
      end
      
      it 'converts security code to string' do
        expect(proxy).to receive(:send_command) do |component_id, command_list, opts|
          security_command = command_list.find { |cmd| cmd["n"] == "securityCode" }
          expect(security_command["v"]).to eq("1234")
        end
        
        proxy.set_plan(plan_nr, security_code: security_code)
      end
    end
    
    context 'when proxy is not ready' do
      before do
        allow(proxy).to receive(:validate_ready).and_raise(RSMP::NotReady.new("not ready"))
      end
      
      it 'raises NotReady error' do
        expect { proxy.set_plan(plan_nr, security_code: security_code) }.to raise_error(RSMP::NotReady)
      end
    end
    
    context 'when main component is not found' do
      before do
        allow(proxy).to receive(:validate_ready)
        proxy.instance_variable_set(:@components, {})
      end
      
      it 'raises error' do
        expect { proxy.set_plan(plan_nr, security_code: security_code) }.to raise_error("TLC main component not found")
      end
    end
  end
  
  describe '#fetch_signal_plan' do
    let(:expected_status_list) do
      [
        {
          "sCI" => "S0014",
          "n" => "status"
        },
        {
          "sCI" => "S0014", 
          "n" => "source"
        }
      ]
    end
    
    context 'when proxy is ready' do
      before do
        allow(proxy).to receive(:validate_ready)
        allow(proxy).to receive(:request_status).and_return({ sent: double('message') })
      end
      
      it 'sends S0014 status request with correct parameters' do
        expect(proxy).to receive(:request_status).with('TLC001', expected_status_list, {})
        
        proxy.fetch_signal_plan
      end
      
      it 'accepts options parameter' do
        options = { collect: true }
        expect(proxy).to receive(:request_status).with('TLC001', expected_status_list, options)
        
        proxy.fetch_signal_plan(options: options)
      end
    end
    
    context 'when proxy is not ready' do
      before do
        allow(proxy).to receive(:validate_ready).and_raise(RSMP::NotReady.new("not ready"))
      end
      
      it 'raises NotReady error' do
        expect { proxy.fetch_signal_plan }.to raise_error(RSMP::NotReady)
      end
    end
    
    context 'when main component is not found' do
      before do
        allow(proxy).to receive(:validate_ready)
        proxy.instance_variable_set(:@components, {})
      end
      
      it 'raises error' do
        expect { proxy.fetch_signal_plan }.to raise_error("TLC main component not found")
      end
    end
  end
end