RSpec.describe RSMP::TLC::TrafficControllerProxy do
  let(:supervisor_settings) do
    {
      'port' => 13_113,
      'default' => {
        'sxl' => 'tlc',
        'type' => 'tlc',
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

  let(:proxy) do
    supervisor = RSMP::Supervisor.new(
      supervisor_settings: supervisor_settings,
      log_settings: { 'active' => false }
    )

    described_class.new(
      supervisor: supervisor,
      ip: '127.0.0.1',
      port: 12_345,
      site_id: 'TLC001'
    )
  end

  describe 'initialize' do
    it 'initializes with nil status values' do
      expect(proxy.current_plan).to be_nil
      expect(proxy.plan_source).to be_nil
      expect(proxy.timeplan).to be_nil
      expect(proxy.functional_position).to be_nil
      expect(proxy.yellow_flash).to be_nil
      expect(proxy.traffic_situation).to be_nil
    end

    it 'retrieves timeouts from supervisor settings, merged with defaults' do
      expected = RSMP::Supervisor::Options.new({}).to_h.dig('default', 'timeouts')
                                          .merge(supervisor_settings['default']['timeouts'])
      expect(proxy.timeouts).to eq(expected)
    end

    it 'is a subclass of SiteProxy' do
      expect(proxy).to be_a(RSMP::SiteProxy)
    end
  end

  describe 'status value storage' do
    before do
      main_component = RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true)
      proxy.instance_variable_set(:@main, main_component)
      proxy.instance_variable_set(:@state, :connected)
    end

    it 'updates timeplan and plan_source when processing S0014 status updates' do
      status_update = RSMP::StatusUpdate.new(
        'mId' => 'abc123',
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [
          { 'sCI' => 'S0014', 'n' => 'status', 's' => '3', 'q' => 'recent' },
          { 'sCI' => 'S0014', 'n' => 'source', 's' => 'forced', 'q' => 'recent' }
        ]
      )

      proxy.process_status_update(status_update)

      expect(proxy.timeplan).to eq(3)
      expect(proxy.current_plan).to eq(3)
      expect(proxy.plan_source).to eq('forced')
    end

    it 'caches functional_position from S0007 status updates' do
      status_update = RSMP::StatusUpdate.new(
        'mId' => 'abc124',
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0007', 'n' => 'status', 's' => 'True', 'q' => 'recent' }]
      )
      proxy.process_status_update(status_update)
      expect(proxy.functional_position).to eq('True')
    end

    it 'caches yellow_flash from S0011 status updates' do
      status_update = RSMP::StatusUpdate.new(
        'mId' => 'abc125',
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0011', 'n' => 'status', 's' => 'True,True', 'q' => 'recent' }]
      )
      proxy.process_status_update(status_update)
      expect(proxy.yellow_flash).to eq('True,True')
    end

    it 'caches traffic_situation from S0015 status updates' do
      status_update = RSMP::StatusUpdate.new(
        'mId' => 'abc126',
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0015', 'n' => 'status', 's' => '3', 'q' => 'recent' }]
      )
      proxy.process_status_update(status_update)
      expect(proxy.traffic_situation).to eq('3')
    end

    it 'returns timeplan attributes from main component' do
      proxy.instance_variable_get(:@main).instance_variable_set(
        :@statuses, { 'S0014' => { 'status' => { 's' => '2', 'q' => 'recent' } } }
      )
      expect(proxy.timeplan_attributes).to eq({ 'status' => { 's' => '2', 'q' => 'recent' } })
    end

    it 'returns empty hash when no main component' do
      proxy.instance_variable_set(:@main, nil)
      expect(proxy.timeplan_attributes).to eq({})
    end
  end

  describe 'method functionality' do
    before do
      proxy.instance_variable_set(:@main, RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true))
    end

    {
      set_timeplan: [3],
      set_functional_position: ['YellowFlash'],
      set_traffic_situation: [1],
      unset_traffic_situation: [],
      set_fixed_time: ['True'],
      set_inputs: ['00000000'],
      set_week_table: ['0-1,0-1,0-1,0-1,0-1,0-6,0-6'],
      set_day_table: ['0-22:0-0'],
      set_trigger_level: ['1'],
      set_dynamic_bands_timeout: ['20'],
      fetch_signal_plan: [],
      subscribe_to_timeplan: []
    }.each do |method, args|
      it "validates proxy is ready before #{method}" do
        expect { proxy.send(method, *args) }.to raise_error(RSMP::NotReady)
      end
    end

    {
      set_emergency_route: [{ route: 1, active: true }],
      set_input: [{ input: 1, status: 'True' }],
      set_dynamic_bands: [{ plan: 1, status: '1-1' }],
      set_offset: [{ plan: 1, offset: 0 }],
      set_cycle_time: [{ plan: 1, cycle_time: 6 }],
      force_input: [{ input: 1, status: 'True', value: 'True' }],
      force_output: [{ output: 1, status: 'True', value: 'True' }],
      set_security_code: [{ level: 2, old_code: '0000', new_code: '1111' }]
    }.each do |method, kwargs|
      it "validates proxy is ready before #{method} with keyword args" do
        expect { proxy.send(method, **kwargs.first) }.to raise_error(RSMP::NotReady)
      end
    end

    it 'validates proxy is ready before wait_for_status' do
      expect do
        proxy.wait_for_status('test status', [{ 'sCI' => 'S0014', 'n' => 'status', 's' => '1' }])
      end.to raise_error(RSMP::NotReady)
    end

    it 'validates proxy is ready before force_detector_logic' do
      expect do
        proxy.force_detector_logic('DL1', status: 'True', mode: 'True')
      end.to raise_error(RSMP::NotReady)
    end

    it 'validates proxy is ready before order_signal_start' do
      expect { proxy.order_signal_start('SG1') }.to raise_error(RSMP::NotReady)
    end

    it 'validates proxy is ready before order_signal_stop' do
      expect { proxy.order_signal_stop('SG1') }.to raise_error(RSMP::NotReady)
    end

    it 'validates proxy is ready before set_clock' do
      expect { proxy.set_clock(Time.now) }.to raise_error(RSMP::NotReady)
    end

    it 'raises error when main component is missing for set_timeplan' do
      proxy.instance_variable_set(:@main, nil)
      proxy.instance_variable_set(:@state, :ready)

      expect { proxy.set_timeplan(3) }.to raise_error('TLC main component not found')
    end

    context 'with within: parameter' do
      {
        set_timeplan: [3],
        set_functional_position: ['YellowFlash'],
        set_traffic_situation: [1],
        unset_traffic_situation: [],
        set_fixed_time: ['True'],
        set_inputs: ['00000000'],
        set_week_table: ['0-1,0-1,0-1,0-1,0-1,0-6,0-6'],
        set_day_table: ['0-22:0-0'],
        set_trigger_level: ['1'],
        set_dynamic_bands_timeout: ['20']
      }.each do |method, args|
        it "validates proxy is ready before #{method} with within:" do
          expect { proxy.send(method, *args, within: 5) }.to raise_error(RSMP::NotReady)
        end
      end

      {
        set_emergency_route: [{ route: 1, active: true }],
        set_input: [{ input: 1, status: 'True' }],
        set_dynamic_bands: [{ plan: 1, status: '1-1' }],
        set_offset: [{ plan: 1, offset: 0 }],
        set_cycle_time: [{ plan: 1, cycle_time: 6 }],
        force_input: [{ input: 1, status: 'True', value: 'True' }],
        force_output: [{ output: 1, status: 'True', value: 'True' }],
        set_security_code: [{ level: 2, old_code: '0000', new_code: '1111' }]
      }.each do |method, kwargs|
        it "validates proxy is ready before #{method} with within: and keyword args" do
          expect { proxy.send(method, **kwargs.first, within: 5) }.to raise_error(RSMP::NotReady)
        end
      end

      it 'validates proxy is ready before force_detector_logic with within:' do
        expect do
          proxy.force_detector_logic('DL1', status: 'True', mode: 'True', within: 5)
        end.to raise_error(RSMP::NotReady)
      end

      it 'validates proxy is ready before order_signal_start with within:' do
        expect { proxy.order_signal_start('SG1', within: 5) }.to raise_error(RSMP::NotReady)
      end

      it 'validates proxy is ready before order_signal_stop with within:' do
        expect { proxy.order_signal_stop('SG1', within: 5) }.to raise_error(RSMP::NotReady)
      end

      it 'validates proxy is ready before set_clock with within:' do
        expect { proxy.set_clock(Time.now, within: 5) }.to raise_error(RSMP::NotReady)
      end
    end

    it 'validates proxy is ready before request_status' do
      expect do
        proxy.request_status({ S0014: [:status] }, within: 5)
      end.to raise_error(RSMP::NotReady)
    end
  end

  describe 'security_code_for' do
    context 'when security codes are configured with integer keys' do
      before do
        proxy.instance_variable_set(:@site_settings, { 'security_codes' => { 1 => 'alpha', 2 => 'beta' } })
      end

      it 'returns the code for level 1' do
        expect(proxy.send(:security_code_for, 1)).to eq('alpha')
      end

      it 'returns the code for level 2' do
        expect(proxy.send(:security_code_for, 2)).to eq('beta')
      end
    end

    context 'when security codes are configured with string keys' do
      before do
        proxy.instance_variable_set(:@site_settings, { 'security_codes' => { '1' => 'alpha', '2' => 'beta' } })
      end

      it 'returns the code for level 1 (string key fallback)' do
        expect(proxy.send(:security_code_for, 1)).to eq('alpha')
      end
    end

    context 'when security code is missing' do
      before do
        proxy.instance_variable_set(:@site_settings, { 'security_codes' => {} })
      end

      it 'raises ArgumentError' do
        expect { proxy.send(:security_code_for, 2) }.to raise_error(ArgumentError, /level 2/)
      end
    end

    context 'when site_settings is nil' do
      before do
        proxy.instance_variable_set(:@site_settings, nil)
      end

      it 'raises ArgumentError' do
        expect { proxy.send(:security_code_for, 1) }.to raise_error(ArgumentError, /level 1/)
      end
    end
  end

  describe 'use_soc?' do
    it 'returns false when core_version is nil' do
      proxy.instance_variable_set(:@core_version, nil)
      expect(proxy.send(:use_soc?)).to be false
    end

    it 'returns false for core version below 3.1.5' do
      proxy.instance_variable_set(:@core_version, '3.1.4')
      expect(proxy.send(:use_soc?)).to be false
    end

    it 'returns true for core version 3.1.5' do
      proxy.instance_variable_set(:@core_version, '3.1.5')
      expect(proxy.send(:use_soc?)).to be true
    end

    it 'returns true for core version above 3.1.5' do
      proxy.instance_variable_set(:@core_version, '3.2.0')
      expect(proxy.send(:use_soc?)).to be true
    end
  end

  describe 'functional_position_confirm_status' do
    it 'returns S0011 True pattern for YellowFlash' do
      result = proxy.send(:functional_position_confirm_status, 'YellowFlash')
      expect(result).to eq([{ 'sCI' => 'S0011', 'n' => 'status', 's' => /^True(,True)*$/ }])
    end

    it 'returns S0007 False pattern for Dark' do
      result = proxy.send(:functional_position_confirm_status, 'Dark')
      expect(result).to eq([{ 'sCI' => 'S0007', 'n' => 'status', 's' => /^False(,False)*$/ }])
    end

    it 'returns S0007, S0011, S0005 for NormalControl' do
      result = proxy.send(:functional_position_confirm_status, 'NormalControl')
      expect(result).to eq([
                             { 'sCI' => 'S0007', 'n' => 'status', 's' => /^True(,True)*$/ },
                             { 'sCI' => 'S0011', 'n' => 'status', 's' => /^False(,False)*$/ },
                             { 'sCI' => 'S0005', 'n' => 'status', 's' => 'False' }
                           ])
    end

    it 'returns empty array for unknown status' do
      result = proxy.send(:functional_position_confirm_status, 'Unknown')
      expect(result).to eq([])
    end
  end

  describe 'send_command_with_confirm' do
    before do
      proxy.instance_variable_set(:@main, RSMP::ComponentProxy.new(id: 'TLC001', node: proxy, grouped: true))
      proxy.instance_variable_set(:@site_settings, { 'security_codes' => { 2 => '2222' } })
    end

    it 'returns without waiting when no within: is given' do
      allow(proxy).to receive(:wait_for_status)
      proxy.instance_variable_set(:@state, :ready)
      allow(proxy).to receive(:send_command).and_return({ sent: double })
      proxy.send(:send_command_with_confirm, 'TLC001', [], 'test', [{ 'sCI' => 'S0014', 'n' => 'status', 's' => '1' }])
      expect(proxy).not_to have_received(:wait_for_status)
    end

    it 'skips wait_for_status when confirm_status_list is nil' do
      allow(proxy).to receive(:wait_for_status)
      proxy.instance_variable_set(:@state, :ready)
      allow(proxy).to receive(:send_command).and_return({ sent: double })
      proxy.send(:send_command_with_confirm, 'TLC001', [], 'test', nil, within: 1)
      expect(proxy).not_to have_received(:wait_for_status)
    end
  end
end
