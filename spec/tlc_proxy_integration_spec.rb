require 'spec_helper'

RSpec.describe 'TLCProxy Integration' do
  describe 'M0002 and S0014 message format' do
    let(:supervisor_settings) { { 'sites' => {}, 'guest' => {} } }
    let(:supervisor) { double('supervisor', supervisor_settings: supervisor_settings) }
    let(:site_id) { 'RN+SI0001' }
    let(:options) { { supervisor: supervisor, site_id: site_id } }
    let(:proxy) { RSMP::TLCProxy.new(options) }

    before do
      allow_any_instance_of(RSMP::TLCProxy).to receive(:initialize_components)
      allow(proxy).to receive(:send_command).and_return(double('command_message'))
      allow(proxy).to receive(:request_status).and_return(double('status_message'))
      allow(proxy).to receive(:main).and_return(double('main_component', c_id: 'TC'))
    end

    describe 'set_plan method' do
      it 'generates correct M0002 command format for RSMP TLC' do
        plan_number = 3
        security_code = '2222'
        
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

        expect(proxy).to receive(:send_command).with('TC', expected_command_list, {})
        proxy.set_plan(plan_number, security_code: security_code)
      end

      it 'allows passing additional options' do
        plan_number = 1
        security_code = '2222'
        additional_options = { timeout: 5, collect: true }
        
        expect(proxy).to receive(:send_command).with('TC', anything, additional_options)
        proxy.set_plan(plan_number, security_code: security_code, **additional_options)
      end
    end

    describe 'fetch_signal_plan method' do
      it 'generates correct S0014 status request format for RSMP TLC' do
        expected_status_list = [{
          'sCI' => 'S0014',
          'n' => 'status'
        }, {
          'sCI' => 'S0014', 
          'n' => 'source'
        }]

        expect(proxy).to receive(:request_status).with('TC', expected_status_list, {})
        proxy.fetch_signal_plan
      end

      it 'allows passing additional options' do
        additional_options = { timeout: 5, collect: true }
        
        expect(proxy).to receive(:request_status).with('TC', anything, additional_options)
        proxy.fetch_signal_plan(**additional_options)
      end
    end

    describe 'example usage' do
      it 'demonstrates typical TLC proxy workflow' do
        # This would be typical usage in a supervisor connecting to a remote TLC
        
        # Change to signal plan 2 with security code
        expect(proxy).to receive(:send_command).with('TC', anything, {})
        proxy.set_plan(2, security_code: '2222')
        
        # Fetch the current signal plan to verify
        expect(proxy).to receive(:request_status).with('TC', anything, {})
        proxy.fetch_signal_plan
      end
    end
  end
end