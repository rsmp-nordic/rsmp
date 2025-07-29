RSpec.describe RSMP::TLCProxy do
  let(:supervisor) { double('supervisor', supervisor_settings: { 'intervals' => { 'timer' => 1 } }) }
  let(:options) do
    {
      supervisor: supervisor,
      site_id: 'test_site',
      settings: { 'intervals' => { 'timer' => 1 } },
      socket: double('socket'),
      stream: double('stream'),
      protocol: double('protocol'),
      ip: '127.0.0.1',
      port: 12345,
      info: {}
    }
  end
  
  let(:proxy) { RSMP::TLCProxy.new(options) }
  let(:main_component) { double('main_component', c_id: 'main_001') }

  before do
    allow(proxy).to receive(:initialize_components)
    allow(proxy).to receive(:main).and_return(main_component)
    allow(proxy).to receive(:validate_ready)
    allow(proxy).to receive(:send_command).and_return({ sent: double('message') })
    allow(proxy).to receive(:request_status).and_return({ sent: double('message') })
  end

  describe '#change_signal_plan' do
    it 'sends M0002 command with correct parameters' do
      timeplan = 3
      security_code = "1234"
      options = { validate: true }

      expected_command_list = [
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
          "v" => security_code
        },
        {
          "cCI" => "M0002",
          "cO" => "setPlan",
          "n" => "timeplan",
          "v" => timeplan.to_s
        }
      ]

      result = proxy.change_signal_plan(timeplan, security_code, options)

      expect(proxy).to have_received(:validate_ready).with('change signal plan')
      expect(proxy).to have_received(:send_command).with('main_001', expected_command_list, options)
      expect(result).to have_key(:sent)
    end

    it 'uses "main" as default component id when main is nil' do
      allow(proxy).to receive(:main).and_return(nil)
      
      proxy.change_signal_plan(1, "1234")
      
      expect(proxy).to have_received(:send_command).with('main', anything, anything)
    end

    it 'converts timeplan to string' do
      proxy.change_signal_plan(5, "1234")
      
      expected_command = hash_including(
        "n" => "timeplan",
        "v" => "5"
      )
      
      expect(proxy).to have_received(:send_command) do |_, command_list, _|
        expect(command_list).to include(expected_command)
      end
    end
  end

  describe '#fetch_signal_plan' do
    it 'sends S0014 status request with correct parameters' do
      options = { validate: true }

      expected_status_list = [
        {
          "sCI" => "S0014",
          "n" => "status"
        },
        {
          "sCI" => "S0014", 
          "n" => "source"
        }
      ]

      result = proxy.fetch_signal_plan(options)

      expect(proxy).to have_received(:validate_ready).with('fetch signal plan')
      expect(proxy).to have_received(:request_status).with('main_001', expected_status_list, options)
      expect(result).to have_key(:sent)
    end

    it 'uses "main" as default component id when main is nil' do
      allow(proxy).to receive(:main).and_return(nil)
      
      proxy.fetch_signal_plan
      
      expect(proxy).to have_received(:request_status).with('main', anything, anything)
    end

    it 'works without options' do
      proxy.fetch_signal_plan
      
      expect(proxy).to have_received(:request_status).with(anything, anything, {})
    end
  end
end