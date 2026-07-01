require_relative '../support/site_proxy_stub'

describe RSMP::Proxy do
  class CapturingProtocol
    attr_reader :lines

    def initialize
      @lines = []
    end

    def write_lines(line)
      @lines << line
    end
  end

  class RejectingSxlInterface
    def validate_message!(_message)
      raise RSMP::MessageRejected, 'SXL says no'
    end
  end

  class CapturingSxlInterface
    attr_reader :messages

    def initialize
      @messages = []
    end

    def validate_message!(_message); end

    def process_message(message)
      @messages << message
    end
  end

  let(:options) { {} }
  let(:proxy) { subject.new options }

  with '#wait_for_state' do
    it 'wakes up' do
      task = Async::Task.current
      subtask = task.async do |_subtask|
        proxy.wait_for_state :connected, timeout: 0.001
      end
      proxy.state = :connected
      expect(subtask.wait).to be == true
    end

    it 'accepts array of states and returns current state' do
      task = Async::Task.current
      subtask = task.async do |_subtask|
        state = proxy.wait_for_state %i[ok ready], timeout: 0.001
        expect(state).to be == :ready
      end
      proxy.state = :ready
      subtask.result
    end

    it 'times out' do
      expect do
        proxy.wait_for_state :connected, timeout: 0.001
      end.to raise_exception(RSMP::TimeoutError)
    end

    it 'returns immediately if state is already correct' do
      proxy.state = :disconnected
      proxy.instance_variable_set(:@state_condition, Async::Notification.new)
      result = proxy.wait_for_state :disconnected, timeout: 0.001
      expect(result).to be == true
    end
  end

  with '#wait_for_condition without block' do
    it 'wakes up' do
      task = Async::Task.current
      condition = Async::Notification.new
      subtask = task.async do |_subtask|
        result = proxy.wait_for_condition condition, timeout: 0.001
        expect(result).to be_truthy
      end
      condition.signal
      subtask.result
    end

    it 'times out' do
      condition = Async::Notification.new
      expect do
        proxy.wait_for_condition condition, timeout: 0.001
      end.to raise_exception(RSMP::TimeoutError)
    end
  end

  with '#wait_for_condition with block' do
    it 'wakes up' do
      task = Async::Task.current
      condition = Async::Notification.new
      result_condition = Async::Notification.new
      result = nil
      subtask = task.async do |_subtask|
        proxy.wait_for_condition condition, timeout: 1 do |state|
          result = (state == :banana)
          result_condition.signal
          result
        end
      end
      condition.signal :pear
      result_condition.wait
      expect(result).to be == false

      condition.signal :apple
      result_condition.wait
      expect(result).to be == false

      condition.signal :banana
      result_condition.wait
      expect(result).to be == true

      subtask.result
    end
  end

  with 'version_meets_requirement?' do
    it 'is equal to' do
      expect(subject.version_meets_requirement?('1.0.9', '1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.10', '1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.11', '1.0.10')).to be == false
    end

    it 'is greater than' do
      expect(subject.version_meets_requirement?('1.0.9', '>1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.10', '>1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.11', '>1.0.10')).to be == true
    end

    it 'is greater than or equal to' do
      expect(subject.version_meets_requirement?('1.0.9', '>=1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.10', '>=1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.11', '>=1.0.10')).to be == true
    end

    it 'is less than' do
      expect(subject.version_meets_requirement?('1.0.9', '<1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.10', '<1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.11', '<1.0.10')).to be == false
    end

    it 'is less than or equal to' do
      expect(subject.version_meets_requirement?('1.0.9', '<=1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.10', '<=1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.11', '<=1.0.10')).to be == false
    end

    it 'takes a list of conditions' do
      expect(subject.version_meets_requirement?('1.0.9', ['>=1.0.10', '<1.0.12'])).to be == false
      expect(subject.version_meets_requirement?('1.0.10', ['>=1.0.10', '<1.0.12'])).to be == true
      expect(subject.version_meets_requirement?('1.0.11', ['>=1.0.10', '<1.0.12'])).to be == true
      expect(subject.version_meets_requirement?('1.0.12', ['>=1.0.10', '<1.0.12'])).to be == false
    end
  end

  with 'SXL interfaces' do
    let(:supervisor_settings) do
      {
        'port' => 13_111,
        'default' => {
          'sxls' => { 'tlc' => RSMP::Schema.latest_version(:tlc) },
          'timeouts' => {}
        }
      }
    end

    let(:supervisor) do
      RSMP::Supervisor.new(
        supervisor_settings: supervisor_settings,
        log_settings: { 'active' => false }
      )
    end

    let(:site_proxy) do
      RSMP::SiteProxy.new(
        supervisor: supervisor,
        ip: '127.0.0.1',
        port: 12_345,
        site_id: 'TLC001'
      )
    end

    it 'builds a TLC interface for accepted TLC connections' do
      site_proxy.instance_variable_set(
        :@accepted_sxls,
        [{ 'name' => 'tlc', 'version' => RSMP::Schema.latest_version(:tlc) }]
      )

      site_proxy.build_sxl_interfaces

      expect(site_proxy.sxl_interfaces.keys).to be == ['tlc']
      expect(site_proxy.sxl_interface('tlc')).to be_a(RSMP::TLC::SupervisorInterface)
      expect(site_proxy.tlc).to be == site_proxy.sxl_interface('tlc')
    end

    it 'raises when requesting an interface that was not accepted' do
      expect do
        site_proxy.tlc
      end.to raise_exception(RSMP::Schema::UnknownSchemaTypeError, message: be =~ /tlc/)
    end

    it 'builds generic SiteProxy connections from the supervisor' do
      built_proxy = supervisor.build_proxy(
        supervisor: supervisor,
        ip: '127.0.0.1',
        port: 12_345,
        site_id: 'TLC001'
      )

      expect(built_proxy).to be_a(RSMP::SiteProxy)
    end

    it 'sends MessageNotAck when an SXL interface rejects an incoming message before generic acknowledgement' do
      protocol = CapturingProtocol.new
      site_proxy.instance_variable_set(:@protocol, protocol)
      site_proxy.instance_variable_set(:@state, :connected)
      site_proxy.instance_variable_set(:@core_version, '3.3.0')
      site_proxy.instance_variable_set(:@version_determined, true)
      site_proxy.instance_variable_set(
        :@accepted_sxls,
        [{ 'name' => 'tlc', 'version' => RSMP::Schema.latest_version(:tlc) }]
      )
      site_proxy.instance_variable_set(:@sxl_interfaces, { 'tlc' => RejectingSxlInterface.new })

      site_proxy.process_packet({
        'mType' => 'rSMsg',
        'type' => 'StatusUpdate',
        'cId' => 'C1',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => '1', 'q' => 'recent' }],
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda'
      }.to_json)

      response = JSON.parse(protocol.lines.last)
      expect(response['type']).to be == 'MessageNotAck'
      expect(response['oMId']).to be == '859e189e-c973-4b40-90c4-45a7a25f2dda'
      expect(response['rea']).to be == 'SXL says no'
    end

    it 'sends MessageNotAck when no accepted SXL defines an incoming message code' do
      protocol = CapturingProtocol.new
      site_proxy.instance_variable_set(:@protocol, protocol)
      site_proxy.instance_variable_set(:@state, :connected)
      site_proxy.instance_variable_set(:@core_version, '3.3.0')
      site_proxy.instance_variable_set(:@version_determined, true)
      site_proxy.instance_variable_set(
        :@accepted_sxls,
        [{ 'name' => 'tlc', 'version' => RSMP::Schema.latest_version(:tlc) }]
      )

      site_proxy.process_packet({
        'mType' => 'rSMsg',
        'type' => 'StatusUpdate',
        'cId' => 'C1',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0000', 'n' => 'status', 's' => '1', 'q' => 'recent' }],
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda'
      }.to_json)

      response = JSON.parse(protocol.lines.last)
      expect(response['type']).to be == 'MessageNotAck'
      expect(response['oMId']).to be == '859e189e-c973-4b40-90c4-45a7a25f2dda'
      expect(response['rea']).to be =~ /No accepted SXL defines status code\(s\) S0000/
    end

    it 'dispatches supervisor-side SXL requests to the interface without generic pre-processing' do
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'TLC001',
          'supervisors' => [],
          'sxls' => { 'tlc' => RSMP::Schema.latest_version(:tlc) }
        },
        log_settings: { 'active' => false }
      )
      supervisor_proxy = RSMP::SupervisorProxy.new(
        site: site,
        ip: '127.0.0.1',
        port: 12_345
      )
      supervisor_proxy.instance_variable_set(:@core_version, '3.3.0')
      supervisor_proxy.instance_variable_set(
        :@accepted_sxls,
        [{ 'name' => 'tlc', 'version' => RSMP::Schema.latest_version(:tlc) }]
      )
      interface = CapturingSxlInterface.new
      supervisor_proxy.instance_variable_set(:@sxl_interfaces, { 'tlc' => interface })

      generic_calls = 0
      supervisor_proxy.define_singleton_method(:process_sxl_request) do |_message|
        generic_calls += 1
      end

      message = RSMP::StatusRequest.new(
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda',
        'cId' => 'TLC001',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus' }]
      )

      supervisor_proxy.process_message message

      expect(interface.messages).to be == [message]
      expect(generic_calls).to be == 0
    end

    it 'lets the default site-side interface delegate request processing to the proxy' do
      handled = nil
      proxy = Object.new
      proxy.define_singleton_method(:process_sxl_request) do |message|
        handled = message
      end
      message = RSMP::CommandRequest.new(
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda',
        'cId' => 'TLC001',
        'arg' => [{ 'cCI' => 'M0001', 'n' => 'status', 'cO' => 'setValue', 'v' => 'true' }]
      )

      interface = RSMP::SXL::SiteInterface.new(proxy: proxy, name: 'tlc', version: '1.2.1')
      interface.process_message message

      expect(handled).to be == message
    end

    it 'decodes incoming SXL values after validating raw wire values' do
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'TLC001',
          'supervisors' => [],
          'sxls' => { 'tlc' => '1.3.0' },
          'core_version' => '3.3.0'
        },
        log_settings: { 'active' => false }
      )
      supervisor_proxy = RSMP::SupervisorProxy.new(site: site, ip: '127.0.0.1', port: 12_345)
      supervisor_proxy.instance_variable_set(:@core_version, '3.3.0')
      supervisor_proxy.instance_variable_set(:@version_determined, true)
      supervisor_proxy.instance_variable_set(:@accepted_sxls, [{ 'name' => 'tlc', 'version' => '1.3.0' }])
      interface = CapturingSxlInterface.new
      supervisor_proxy.instance_variable_set(:@sxl_interfaces, { 'tlc' => interface })

      json = {
        'mType' => 'rSMsg',
        'type' => 'CommandRequest',
        'cId' => 'TLC001',
        'arg' => [
          { 'cCI' => 'M0019', 'cO' => 'setInput', 'n' => 'status', 'v' => 'True' },
          { 'cCI' => 'M0019', 'cO' => 'setInput', 'n' => 'securityCode', 'v' => '1111' },
          { 'cCI' => 'M0019', 'cO' => 'setInput', 'n' => 'input', 'v' => '3' },
          { 'cCI' => 'M0019', 'cO' => 'setInput', 'n' => 'inputValue', 'v' => 'False' }
        ],
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda'
      }.to_json

      supervisor_proxy.process_packet json

      message = interface.messages.first
      expect(message.json).to be == json
      expect(message.attributes['arg'].map { |item| item['v'] }).to be == [true, '1111', 3, false]
    end

    it 'skips incoming decoding when validation is skipped' do
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'TLC001',
          'supervisors' => [],
          'sxls' => { 'tlc' => '1.3.0' },
          'core_version' => '3.3.0'
        },
        log_settings: { 'active' => false }
      )
      supervisor_proxy = RSMP::SupervisorProxy.new(site: site, ip: '127.0.0.1', port: 12_345)
      supervisor_proxy.instance_variable_get(:@site_settings)['skip_validation'] = ['CommandRequest']
      supervisor_proxy.instance_variable_set(:@core_version, '3.3.0')
      supervisor_proxy.instance_variable_set(:@version_determined, true)
      supervisor_proxy.instance_variable_set(:@accepted_sxls, [{ 'name' => 'tlc', 'version' => '1.3.0' }])
      interface = CapturingSxlInterface.new
      supervisor_proxy.instance_variable_set(:@sxl_interfaces, { 'tlc' => interface })

      supervisor_proxy.process_packet({
        'mType' => 'rSMsg',
        'type' => 'CommandRequest',
        'cId' => 'TLC001',
        'arg' => [{ 'cCI' => 'M0019', 'cO' => 'setInput', 'n' => 'inputValue', 'v' => 'False' }],
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda'
      }.to_json)

      expect(interface.messages.first.attributes['arg'].first['v']).to be == 'False'
    end
  end

  with 'core 3.3.0 message semantics' do
    def build_core_3_3_supervisor_proxy
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'TLC001',
          'supervisors' => [],
          'sxls' => { 'tlc' => '1.3.0' },
          'core_version' => '3.3.0'
        },
        log_settings: { 'active' => false }
      )
      protocol = CapturingProtocol.new
      proxy = RSMP::SupervisorProxy.new(
        site: site,
        ip: '127.0.0.1',
        port: 12_345
      )
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.instance_variable_set(:@core_version, '3.3.0')
      proxy.instance_variable_set(:@version_determined, true)
      proxy.instance_variable_set(:@accepted_sxls, [{ 'name' => 'tlc', 'version' => '1.3.0' }])
      [proxy, protocol]
    end

    def build_core_3_3_site_proxy
      supervisor = RSMP::Supervisor.new(
        supervisor_settings: {
          'default' => {
            'sxls' => { 'tlc' => '1.3.0' },
            'core_version' => '3.3.0'
          }
        },
        log_settings: { 'active' => false }
      )
      protocol = CapturingProtocol.new
      proxy = RSMP::SiteProxy.new(
        supervisor: supervisor,
        ip: '127.0.0.1',
        port: 12_345,
        site_id: 'TLC001'
      )
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.instance_variable_set(:@core_version, '3.3.0')
      proxy.instance_variable_set(:@version_determined, true)
      proxy.instance_variable_set(:@accepted_sxls, [{ 'name' => 'tlc', 'version' => '1.3.0' }])
      [proxy, protocol]
    end

    it 'rejects command requests with multiple command codes' do
      proxy, protocol = build_core_3_3_supervisor_proxy
      message = RSMP::CommandRequest.new(
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda',
        'cId' => 'C1',
        'arg' => [
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'status', 'v' => 'NormalControl' },
          { 'cCI' => 'M0002', 'cO' => 'setValue', 'n' => 'status', 'v' => '1' }
        ]
      )

      proxy.process_command_request message

      response = JSON.parse(protocol.lines.last)
      expect(response['type']).to be == 'MessageNotAck'
      expect(response['rea']).to be =~ /more than one command code/
    end

    it 'rejects command responses with multiple command codes' do
      proxy, protocol = build_core_3_3_site_proxy
      message = RSMP::CommandResponse.new(
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda',
        'cId' => 'C1',
        'cTS' => '2024-01-01T10:00:00.000Z',
        'rvs' => [
          { 'cCI' => 'M0001', 'n' => 'status', 'v' => 'NormalControl', 'age' => 'recent' },
          { 'cCI' => 'M0002', 'n' => 'status', 'v' => '1', 'age' => 'recent' }
        ]
      )

      proxy.process_command_response message

      response = JSON.parse(protocol.lines.last)
      expect(response['type']).to be == 'MessageNotAck'
      expect(response['rea']).to be =~ /more than one command code/
    end

    it 'marks unimplemented commands as unknown in CommandResponse' do
      proxy, protocol = build_core_3_3_supervisor_proxy
      message = RSMP::CommandRequest.new(
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda',
        'cId' => 'C1',
        'arg' => [
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'status', 'v' => 'NormalControl' },
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'securityCode', 'v' => '1111' }
        ]
      )

      proxy.process_command_request message

      response = JSON.parse(protocol.lines.last)
      expect(response['type']).to be == 'CommandResponse'
      expect(response['rvs']).to be == [
        { 'cCI' => 'M0001', 'n' => 'status', 'v' => nil, 'age' => 'unknown' },
        { 'cCI' => 'M0001', 'n' => 'securityCode', 'v' => nil, 'age' => 'unknown' }
      ]
    end

    it 'marks commands as undefined for unknown components in CommandResponse' do
      proxy, protocol = build_core_3_3_supervisor_proxy
      message = RSMP::CommandRequest.new(
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda',
        'cId' => 'bad',
        'arg' => [
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'status', 'v' => 'NormalControl' },
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'securityCode', 'v' => '1111' },
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'timeout', 'v' => '0' },
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'intersection', 'v' => '0' }
        ]
      )

      proxy.process_command_request message

      response = JSON.parse(protocol.lines.last)
      expect(response['type']).to be == 'CommandResponse'
      expect(response['rvs']).to be == [
        { 'cCI' => 'M0001', 'n' => 'status', 'v' => nil, 'age' => 'undefined' },
        { 'cCI' => 'M0001', 'n' => 'securityCode', 'v' => nil, 'age' => 'undefined' },
        { 'cCI' => 'M0001', 'n' => 'timeout', 'v' => nil, 'age' => 'undefined' },
        { 'cCI' => 'M0001', 'n' => 'intersection', 'v' => nil, 'age' => 'undefined' }
      ]
    end

    it 'allows optional command arguments to be omitted' do
      proxy, protocol = build_core_3_3_supervisor_proxy
      message = RSMP::CommandRequest.new(
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda',
        'cId' => 'C1',
        'arg' => [
          { 'cCI' => 'M0022', 'cO' => 'setValue', 'n' => 'requestId', 'v' => 'priority-1' },
          { 'cCI' => 'M0022', 'cO' => 'setValue', 'n' => 'type', 'v' => 'new' },
          { 'cCI' => 'M0022', 'cO' => 'setValue', 'n' => 'level', 'v' => '1' }
        ]
      )

      proxy.process_command_request message

      response = JSON.parse(protocol.lines.last)
      expect(response['type']).to be == 'CommandResponse'
    end

    it 'rejects command requests missing required command arguments' do
      proxy, = build_core_3_3_supervisor_proxy
      message = RSMP::CommandRequest.new(
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda',
        'cId' => 'C1',
        'arg' => [
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'securityCode', 'v' => '1111' },
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'timeout', 'v' => '0' },
          { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'intersection', 'v' => '0' }
        ]
      )

      expect do
        proxy.check_required_command_arguments message
      end.to raise_exception(RSMP::MissingAttribute, message: be =~ /status/)
    end

    it 'marks unimplemented statuses as unknown in StatusResponse' do
      proxy, protocol = build_core_3_3_supervisor_proxy
      message = RSMP::StatusRequest.new(
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda',
        'cId' => 'C1',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus' }]
      )

      proxy.process_status_request message

      response = JSON.parse(protocol.lines.last)
      expect(response['type']).to be == 'StatusResponse'
      expect(response['sS']).to be == [
        { 's' => nil, 'q' => 'unknown', 'sCI' => 'S0001', 'n' => 'signalgroupstatus' }
      ]
    end

    it 'preserves status values for known qualities' do
      proxy, = build_core_3_3_supervisor_proxy

      expect(proxy.rsmpify_value({ 'ok' => true }, 'recent')).to be == { 'ok' => true }
      expect(proxy.rsmpify_value(3, 'recent')).to be == 3
      expect(proxy.rsmpify_value(false, 'recent')).to be == false
      expect(proxy.rsmpify_value('3', 'recent')).to be == '3'
      expect(proxy.rsmpify_value(3, 'unknown')).to be_nil
    end

    it 'does not encode messages sent without validation' do
      proxy, protocol = build_core_3_3_supervisor_proxy
      message = RSMP::StatusUpdate.new(
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'basecyclecounter', 's' => 3, 'q' => 'recent' }]
      )

      proxy.send_message message, validate: false

      sent = JSON.parse(protocol.lines.last)
      expect(sent['sS'].first['s']).to be == 3
    end

    it 'does not add legacy NTS attributes for 3.3.0 messages' do
      proxy, = build_core_3_3_supervisor_proxy
      message = RSMP::StatusRequest.new

      proxy.apply_nts_message_attributes message

      expect(message.attributes.key?('ntsOId')).to be == false
      expect(message.attributes.key?('xNId')).to be == false
    end
  end

  with 'message buffering' do
    def build_supervisor_proxy(message_buffer: {}, core_version: '3.2.2')
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'TLC001',
          'supervisors' => [],
          'sxls' => { 'tlc' => '1.2.1' },
          'message_buffer' => {
            'max_messages' => 10_000,
            'statuses' => true
          }.merge(message_buffer)
        },
        log_settings: { 'active' => false }
      )
      proxy = RSMP::SupervisorProxy.new(
        site: site,
        ip: '127.0.0.1',
        port: 12_345
      )
      proxy.instance_variable_set(:@core_version, core_version)
      proxy
    end

    it 'buffers site-originated aggregated status while disconnected' do
      proxy = build_supervisor_proxy
      message = RSMP::AggregatedStatus.new(
        'cId' => 'C1',
        'aSTS' => '2024-01-01T10:00:00.000Z',
        'fP' => nil,
        'fS' => nil,
        'se' => [false, false, false, false, false, true, false, false]
      )

      proxy.send_message message

      expect(proxy.message_buffer.size).to be == 1
      expect(proxy.message_buffer.first).to be_a(RSMP::AggregatedStatus)
    end

    it 'buffers aggregated status before a core version has been negotiated' do
      proxy = build_supervisor_proxy(core_version: nil)
      component = RSMP::Component.new(id: 'C1', node: proxy.site, grouped: true)

      proxy.send_aggregated_status component

      expect(proxy.message_buffer.size).to be == 1
      expect(proxy.message_buffer.first.attributes['se']).to be == [false, false, false, false, false, true, false, false]
    end

    it 'does not buffer command messages while disconnected' do
      proxy = build_supervisor_proxy
      message = RSMP::CommandResponse.new(
        'cId' => 'C1',
        'cTS' => '2024-01-01T10:00:00.000Z',
        'cCI' => 'M0001',
        'n' => 'status',
        'age' => 'recent',
        'rvs' => [{ 'n' => 'status', 'v' => 'true' }]
      )

      expect { proxy.send_message message }.to raise_exception(RSMP::NotReady)
      expect(proxy.message_buffer).to be == []
    end

    it 'filters buffered status updates by configured selector' do
      proxy = build_supervisor_proxy(
        message_buffer: { 'statuses' => [{ 'sCI' => 'S0001', 'n' => 'status' }] }
      )
      message = RSMP::StatusUpdate.new(
        'cId' => 'C1',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [
          { 'sCI' => 'S0001', 'n' => 'status', 's' => '1', 'q' => 'recent' },
          { 'sCI' => 'S0002', 'n' => 'status', 's' => '2', 'q' => 'recent' }
        ]
      )

      proxy.send_message message

      expect(proxy.message_buffer.size).to be == 1
      expect(proxy.message_buffer.first.attributes['sS']).to be == [
        { 'sCI' => 'S0001', 'n' => 'status', 's' => '1', 'q' => 'recent' }
      ]
    end

    it 'marks buffered status updates as old when flushing with core 3.2 or newer' do
      proxy = build_supervisor_proxy(
        message_buffer: { 'statuses' => true },
        core_version: '3.1.5'
      )
      proxy.send_message RSMP::StatusUpdate.new(
        'cId' => 'C1',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => '1', 'q' => 'recent' }]
      )

      protocol = CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.instance_variable_set(:@core_version, '3.2.2')
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['sS']).to be == [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => '1', 'q' => 'old' }]
      expect(proxy.message_buffer).to be == []
    end

    it 'preserves buffered status update timestamps when flushing' do
      proxy = build_supervisor_proxy(message_buffer: { 'statuses' => true })
      proxy.send_message RSMP::StatusUpdate.new(
        'cId' => 'C1',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => '1', 'q' => 'recent' }]
      )

      protocol = CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['sTs']).to be == '2024-01-01T10:00:00.000Z'
    end

    it 'uses the reconnect core version when flushing buffered aggregated status' do
      proxy = build_supervisor_proxy(core_version: '3.1.2')
      proxy.send_message RSMP::AggregatedStatus.new(
        'cId' => 'C1',
        'aSTS' => '2024-01-01T10:00:00.000Z',
        'fP' => nil,
        'fS' => nil,
        'se' => %w[false false false false false true false false]
      )

      protocol = CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.instance_variable_set(:@core_version, '3.2.2')
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['se']).to be == [false, false, false, false, false, true, false, false]
    end

    it 'preserves buffered aggregated status timestamps when flushing' do
      proxy = build_supervisor_proxy
      proxy.send_message RSMP::AggregatedStatus.new(
        'cId' => 'C1',
        'aSTS' => '2024-01-01T10:00:00.000Z',
        'fP' => nil,
        'fS' => nil,
        'se' => [false, false, false, false, false, true, false, false]
      )

      protocol = CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['aSTS']).to be == '2024-01-01T10:00:00.000Z'
    end

    it 'preserves buffered alarm timestamps when flushing' do
      proxy = build_supervisor_proxy
      proxy.send_message RSMP::AlarmIssue.new(
        'cId' => 'C1',
        'aCId' => 'A0001',
        'xACId' => '',
        'xNACId' => '',
        'aSp' => 'Issue',
        'aTs' => '2024-01-01T10:00:00.000Z',
        'ack' => 'notAcknowledged',
        'sS' => 'notSuspended',
        'aS' => 'Active',
        'cat' => 'D',
        'pri' => '2',
        'rvs' => []
      )

      protocol = CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['aTs']).to be == '2024-01-01T10:00:00.000Z'
    end

    it 'drops the oldest buffered message when the buffer is full' do
      proxy = build_supervisor_proxy(message_buffer: { 'max_messages' => 1 })

      first = RSMP::AlarmIssue.new('cId' => 'C1', 'aCId' => 'A1')
      second = RSMP::AlarmIssue.new('cId' => 'C1', 'aCId' => 'A2')
      proxy.send_message first
      proxy.send_message second

      expect(proxy.message_buffer.size).to be == 1
      expect(proxy.message_buffer.first.attributes['aCId']).to be == 'A2'
    end

    it 'prunes subscriptions that are not configured for buffering' do
      proxy = build_supervisor_proxy(
        message_buffer: { 'statuses' => [{ 'sCI' => 'S0001', 'n' => 'keep' }] }
      )
      proxy.instance_variable_set(
        :@status_subscriptions,
        {
          'C1' => {
            'S0001' => {
              'keep' => { interval: 1, last_sent_at: Time.now },
              'drop' => { interval: 1, last_sent_at: Time.now }
            }
          }
        }
      )

      proxy.prune_unbuffered_status_subscriptions

      subscriptions = proxy.instance_variable_get(:@status_subscriptions)
      expect(subscriptions['C1']['S0001'].keys).to be == ['keep']
    end
  end
end
