RSpec.describe RSMP::TLCProxy do
  let(:site_proxy) { double('SiteProxy') }
  let(:component_id) { 'TC' }
  let(:tlc_proxy) { RSMP::TLCProxy.new(site_proxy, component_id) }

  describe '#initialize' do
    it 'creates a TLC proxy with site proxy and component ID' do
      expect(tlc_proxy.site_proxy).to eq(site_proxy)
      expect(tlc_proxy.component_id).to eq(component_id)
    end

    it 'uses default component ID if not provided' do
      proxy = RSMP::TLCProxy.new(site_proxy)
      expect(proxy.component_id).to eq('TC')
    end
  end

  describe '#set_signal_plan' do
    it 'sends M0002 command with correct parameters' do
      plan_id = 5
      security_code = '1234'
      expected_command_list = [
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'status', 'v' => 'True' },
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'securityCode', 'v' => '1234' },
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'timeplan', 'v' => '5' }
      ]

      expect(site_proxy).to receive(:send_command).with(component_id, expected_command_list, {})

      tlc_proxy.set_signal_plan(plan_id, security_code: security_code)
    end

    it 'uses default security code if not provided' do
      plan_id = 3
      expected_command_list = [
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'status', 'v' => 'True' },
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'securityCode', 'v' => '0000' },
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'timeplan', 'v' => '3' }
      ]

      expect(site_proxy).to receive(:send_command).with(component_id, expected_command_list, {})

      tlc_proxy.set_signal_plan(plan_id)
    end

    it 'passes options to send_command' do
      plan_id = 2
      options = { timeout: 10 }
      expected_command_list = [
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'status', 'v' => 'True' },
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'securityCode', 'v' => '0000' },
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'timeplan', 'v' => '2' }
      ]

      expect(site_proxy).to receive(:send_command).with(component_id, expected_command_list, options)

      tlc_proxy.set_signal_plan(plan_id, options: options)
    end
  end

  describe '#fetch_signal_plan' do
    it 'sends S0014 status request for current signal plan' do
      expected_status_list = [
        { 'sCI' => 'S0014', 'n' => 'status' },
        { 'sCI' => 'S0014', 'n' => 'source' }
      ]

      expect(site_proxy).to receive(:request_status).with(component_id, expected_status_list, {})

      tlc_proxy.fetch_signal_plan
    end

    it 'passes options to request_status' do
      options = { timeout: 5 }
      expected_status_list = [
        { 'sCI' => 'S0014', 'n' => 'status' },
        { 'sCI' => 'S0014', 'n' => 'source' }
      ]

      expect(site_proxy).to receive(:request_status).with(component_id, expected_status_list, options)

      tlc_proxy.fetch_signal_plan(options: options)
    end
  end
end