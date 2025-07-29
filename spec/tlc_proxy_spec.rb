require 'spec_helper'

RSpec.describe RSMP::TLCProxy do
  let(:supervisor_settings) { { 'sites' => {}, 'guest' => {} } }
  let(:supervisor) { double('supervisor', supervisor_settings: supervisor_settings) }
  let(:site_id) { 'test_site' }
  let(:options) { { supervisor: supervisor, site_id: site_id } }

  # Stub the initialize_components method to avoid complex setup
  before do
    allow_any_instance_of(RSMP::TLCProxy).to receive(:initialize_components)
  end

  describe '#initialize' do
    it 'creates a TLC proxy instance' do
      proxy = RSMP::TLCProxy.new(options)
      expect(proxy).to be_a(RSMP::TLCProxy)
      expect(proxy).to be_a(RSMP::SiteProxy)
    end
  end

  describe '#set_plan' do
    let(:proxy) { RSMP::TLCProxy.new(options) }
    let(:main_component) { double('main_component', c_id: 'main') }
    
    before do
      allow(proxy).to receive(:main).and_return(main_component)
      allow(proxy).to receive(:send_command).and_return(double('command_request'))
    end

    it 'sends M0002 command with correct parameters' do
      plan_number = 3
      security_code = '1234'
      
      expected_command_list = [{
        'cCI' => 'M0002',
        'cO' => 'setPlan',
        'n' => 'status',
        'v' => 'True'
      }, {
        'cCI' => 'M0002',
        'cO' => 'setPlan', 
        'n' => 'securityCode',
        'v' => security_code
      }, {
        'cCI' => 'M0002',
        'cO' => 'setPlan',
        'n' => 'timeplan',
        'v' => plan_number.to_s
      }]

      expect(proxy).to receive(:send_command).with('main', expected_command_list, {})
      proxy.set_plan(plan_number, security_code: security_code)
    end

    it 'uses custom component id when provided' do
      plan_number = 2
      security_code = '5678'
      component_id = 'custom_component'
      
      expect(proxy).to receive(:send_command).with(component_id, anything, {})
      proxy.set_plan(plan_number, security_code: security_code, component_id: component_id)
    end

    it 'defaults to main when no component id and no main component' do
      allow(proxy).to receive(:main).and_return(nil)
      
      plan_number = 1
      security_code = '0000'
      
      expect(proxy).to receive(:send_command).with('main', anything, {})
      proxy.set_plan(plan_number, security_code: security_code)
    end
  end

  describe '#fetch_signal_plan' do
    let(:proxy) { RSMP::TLCProxy.new(options) }
    let(:main_component) { double('main_component', c_id: 'main') }
    
    before do
      allow(proxy).to receive(:main).and_return(main_component)
      allow(proxy).to receive(:request_status).and_return(double('status_request'))
    end

    it 'sends S0014 status request with correct parameters' do
      expected_status_list = [{
        'sCI' => 'S0014',
        'n' => 'status'
      }, {
        'sCI' => 'S0014', 
        'n' => 'source'
      }]

      expect(proxy).to receive(:request_status).with('main', expected_status_list, {})
      proxy.fetch_signal_plan
    end

    it 'uses custom component id when provided' do
      component_id = 'custom_component'
      
      expect(proxy).to receive(:request_status).with(component_id, anything, {})
      proxy.fetch_signal_plan(component_id: component_id)
    end

    it 'defaults to main when no component id and no main component' do
      allow(proxy).to receive(:main).and_return(nil)
      
      expect(proxy).to receive(:request_status).with('main', anything, {})
      proxy.fetch_signal_plan
    end
  end
end