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
  end

  with 'message buffering' do
    def build_supervisor_proxy(message_buffer: {}, core_version: '3.2.2')
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'TLC001',
          'supervisors' => [],
          'sxls' => { 'tlc' => '1.2.1' },
          'message_buffer' => {
            'enabled' => true,
            'max_messages' => 10_000,
            'statuses' => []
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
