require_relative '../support/proxy_helper'
require_relative '../support/site_proxy_stub'

describe RSMP::Proxy do
  include ProxyHelper

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

  class FaultySxlInterface
    def validate_message!(_message)
      nil.unexpected_interface_bug
    end
  end

  let(:options) { {} }
  let(:proxy) { subject.new options }

  with 'collect option' do
    let(:collect_timeout) { 0.01 }
    let(:node) do
      RSMP::Site.new(site_settings: { 'supervisors' => [] }, log_settings: { 'active' => false })
    end

    it 'starts a collector using a filter options hash' do
      filter = RSMP::Filter.new(type: 'StatusUpdate', component: 'C1')
      proxy = subject.new(
        node: node,
        collect: { filter: filter, num: 1, timeout: collect_timeout },
        log_settings: { 'active' => false }
      )

      expect(proxy.collector.active?).to be == true
      proxy.distribute RSMP::Watchdog.new
      proxy.distribute RSMP::StatusUpdate.new('cId' => 'C2')
      expect(proxy.collector.messages).to be == []
      expect(proxy.collector.active?).to be == true

      message = RSMP::StatusUpdate.new('cId' => 'C1')
      proxy.distribute message

      expect(proxy.collector.wait!).to be == [message]
      expect(proxy.collector.active?).to be == false
    end

    it 'starts a queue returned by a Proc before messages are consumed' do
      factory = ->(proxy) { RSMP::Queue.new(proxy, filter: RSMP::Filter.new(type: 'StatusUpdate')) }
      proxy = subject.new(node: node, collect: factory)
      message = RSMP::StatusUpdate.new
      proxy.distribute RSMP::Watchdog.new
      proxy.distribute message

      expect(proxy.collector.wait_for_message!(timeout: collect_timeout)).to be == message
      proxy.collector.stop
      expect(proxy.receivers).to be == []
    end

    it 'passes the proxy to a Proc and starts the returned collector' do
      factory_proxy = nil
      collector = nil
      want = [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus' }]
      factory = proc do |proxy|
        factory_proxy = proxy
        collector = RSMP::StatusCollector.new(proxy, want, responses: false, timeout: 0.1)
      end
      proxy = subject.new(node: node, collect: factory, log_settings: { 'active' => false })

      expect(factory_proxy).to be == proxy
      expect(proxy.collector).to be == collector
      expect(collector.active?).to be == true

      recent = RSMP::StatusUpdate.new('sS' => [want.first.merge('n' => 'cyclecounter')])
      recent.direction = :in
      proxy.distribute recent
      expect(collector.messages).to be == []
      expect(collector.active?).to be == true

      buffered = RSMP::StatusUpdate.new('sS' => want)
      buffered.direction = :in
      proxy.distribute buffered

      expect(collector.wait!).to be == [buffered]
      expect(collector.active?).to be == false
    end
  end

  with '#wait_for_state' do
    it 'wakes up' do
      task = Async::Task.current
      subtask = task.async do |_subtask|
        proxy.wait_for_state :connected, timeout: 1
      end
      proxy.state = :connected
      result = subtask.wait
      expect(result.success?).to be == true
      expect(result.value).to be == :connected
    end

    it 'accepts array of states and returns current state' do
      task = Async::Task.current
      subtask = task.async do |_subtask|
        result = proxy.wait_for_state %i[ok ready], timeout: 1
        expect(result.value).to be == :ready
      end
      proxy.state = :ready
      subtask.result
    end

    it 'times out' do
      result = proxy.wait_for_state :connected, timeout: 0.001
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :timeout
    end

    it 'returns immediately if state is already correct' do
      proxy.state = :disconnected
      proxy.instance_variable_set(:@state_condition, Async::Notification.new)
      result = proxy.wait_for_state :disconnected, timeout: 0.001
      expect(result.success?).to be == true
      expect(result.value).to be == :disconnected
    end
  end

  with '#wait_for_condition without block' do
    it 'wakes up' do
      task = Async::Task.current
      condition = Async::Notification.new
      subtask = task.async do |_subtask|
        result = proxy.wait_for_condition condition, timeout: 0.001
        expect(result.success?).to be == true
      end
      condition.signal
      subtask.result
    end

    it 'times out' do
      condition = Async::Notification.new
      result = proxy.wait_for_condition condition, timeout: 0.001
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :timeout
    end

    it 'does not relabel an Async timeout raised by condition processing' do
      task = Async::Task.current
      condition = Async::Notification.new
      waiting = task.async do
        proxy.wait_for_condition(condition, timeout: 1) do
          raise Async::TimeoutError, 'condition processing defect'
        end
      end
      condition.signal

      expect do
        waiting.wait
      end.to raise_exception(Async::TimeoutError, message: be == 'condition processing defect')
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

  with 'reader failure boundaries' do
    it 'returns an expected failure when the peer closes the stream' do
      protocol = Object.new
      protocol.define_singleton_method(:read_line) { nil }
      reader_proxy = subject.new(protocol: protocol, stream: Object.new, log_settings: { 'active' => false })
      reader_proxy.instance_variable_set(:@session_closed, false)
      reader_proxy.define_singleton_method(:log) { |_message, **_options| nil }

      result = reader_proxy.run_reader(0)

      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :disconnected
      expect(result.failure.source).to be == :peer
    end

    it 'does not relabel a processing system error as a transport failure' do
      protocol = Object.new
      protocol.define_singleton_method(:read_line) { '{}' }
      reader_proxy = subject.new(protocol: protocol, stream: Object.new, log_settings: { 'active' => false })
      reader_proxy.instance_variable_set(:@session_closed, false)
      reader_proxy.define_singleton_method(:process_packet) do |_json|
        raise Errno::ENOENT, 'processing defect'
      end

      expect do
        reader_proxy.run_reader(0)
      end.to raise_exception(Errno::ENOENT, message: be =~ /processing defect/)
    end
  end

  with 'timer termination' do
    it 'returns a missing acknowledgement failure without closing from the timer task' do
      message = Struct.new(:timestamp, :type, :m_id_short).new(0, 'Watchdog', '1234')
      proxy.instance_variable_set(:@site_settings, { 'timeouts' => { 'acknowledgement' => 0.5 } })
      proxy.instance_variable_set(:@awaiting_acknowledgement, 'id' => message)
      proxy.define_singleton_method(:log) { |_message, **_options| nil }
      proxy.define_singleton_method(:distribute_event) { |_event| nil }
      proxy.define_singleton_method(:close) { |**| raise 'timer must not own connection teardown' }

      result = proxy.check_ack_timeout(1)

      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :missing_acknowledgement
      expect(result.failure.context[:reason]).to be == :missing_acknowledgement
    end
  end

  with '#core_3_3_0_or_newer?' do
    it 'is false before version negotiation' do
      expect(proxy.core_3_3_0_or_newer?).to be == false
    end

    it 'is false for older Core versions' do
      %w[3.1.2 3.2.2 3.2.10].each do |version|
        proxy.instance_variable_set(:@core_version, version)
        expect(proxy.core_3_3_0_or_newer?).to be == false
      end
    end

    it 'includes later patch, minor and major versions' do
      %w[3.3.0 3.3.1 3.3.10 3.4.0 3.10.0 4.0.0].each do |version|
        proxy.instance_variable_set(:@core_version, version)
        expect(proxy.core_3_3_0_or_newer?).to be == true
      end
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

  RSMP::Schema.core_versions.reject { |version| Gem::Version.new(version) >= Gem::Version.new('3.3.0') }.each do |version|
    with "Core #{version} initial Version validation" do
      let(:version_attributes) do
        { 'RSMP' => [{ 'vers' => '3.3.0' }, { 'vers' => version }],
          'SXL' => '1.3.0', 'siteId' => [{ 'sId' => 'TLC001' }] }
      end

      def negotiating_proxy(direction, version)
        connection = if direction == 'Request'
                       build_site_proxy(core_version: nil, state: :connected, version_determined: false, session_closed: false,
                                        settings: { 'core_version' => version, 'sxls' => { 'tlc' => '1.3.0' } })
                     else
                       site = build_site(core_version: version, 'sxls' => { 'tlc' => '1.3.0' })
                       build_supervisor_proxy(site, core_version: nil, state: :connected, version_determined: false, session_closed: false)
                     end
        connection.setup_site_settings if direction == 'Request'
        connection.define_singleton_method(:version_accepted) { |_message| nil }
        connection
      end

      %w[Request Response].each do |direction|
        it "validates a #{direction} using the selected legacy version and ignores newer fields" do
          connection = negotiating_proxy(direction, version)
          attributes = version_attributes.merge('step' => 'unknown-to-legacy', 'SXLS' => 'unknown-to-legacy',
                                                'futureField' => { 'anything' => true })
          message = RSMP::Version.new(attributes)
          result = connection.process_packet(JSON.generate(message.attributes))
          expect(result.success?).to be == true
          expect(connection.core_version).to be == version
          expect(connection.accepted_sxls.first['version']).to be == '1.3.0'
        end

        it "rejects malformed fields in a #{direction} before legacy handlers access them" do
          [
            { 'siteId' => nil }, { 'siteId' => [] }, { 'siteId' => ['TLC001'] },
            { 'siteId' => [{ 'sId' => 123 }] }, { 'SXL' => [] }, { 'SXL' => 'invalid' }
          ].each do |invalid|
            connection = negotiating_proxy(direction, version)
            message = RSMP::Version.new(version_attributes.merge(invalid))
            result = connection.process_packet(JSON.generate(message.attributes))
            expect(result.failure.code).to be == :protocol_failure
            expect(connection.disconnected?).to be == true
            expect(messages(connection).last['type']).to be == 'MessageNotAck'
          end
        end

        it "rejects missing required fields in a #{direction}" do
          %w[siteId SXL].each do |field|
            connection = negotiating_proxy(direction, version)
            message = RSMP::Version.new(version_attributes.except(field))
            result = connection.process_packet(JSON.generate(message.attributes))
            expect(result.failure.code).to be == :protocol_failure
            expect(connection.disconnected?).to be == true
          end
        end
      end
    end
  end

  with 'Core 3.3 SXL response negotiation' do
    def build_sxl_negotiating_supervisor_proxy
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'TLC001',
          'supervisors' => [],
          'core_version' => '3.3.0',
          'sxls' => { 'tlc' => '1.2' }
        },
        log_settings: { 'active' => false }
      )
      proxy = RSMP::SupervisorProxy.new(site: site, ip: '127.0.0.1', port: 12_345)
      proxy.instance_variable_set(:@core_version, '3.3.0')
      proxy
    end

    it 'accepts the exact canonical SXL version requested by the site' do
      proxy = build_sxl_negotiating_supervisor_proxy
      message = RSMP::Version.new(
        'SXLS' => [{ 'name' => 'tlc', 'status' => 'ok', 'version' => '1.2.0' }],
        'useAlarms' => true
      )

      proxy.check_sxl_version message

      expect(proxy.accepted_sxls).to be == [{ 'name' => 'tlc', 'status' => 'ok', 'version' => '1.2.0' }]
    end

    it 'rejects a noncanonical SXL version returned by the supervisor' do
      proxy = build_sxl_negotiating_supervisor_proxy
      message = RSMP::Version.new(
        'SXLS' => [{ 'name' => 'tlc', 'status' => 'ok', 'version' => '1.2' }],
        'useAlarms' => true
      )

      expect do
        proxy.check_sxl_version message
      end.to raise_exception(RSMP::HandshakeError, message: be(:include?, 'match the request exactly'))
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
      protocol = ProxyHelper::CapturingProtocol.new
      site_proxy.instance_variable_set(:@protocol, protocol)
      site_proxy.instance_variable_set(:@state, :ready)
      site_proxy.instance_variable_set(:@core_version, '3.3.0')
      site_proxy.instance_variable_set(:@version_determined, true)
      site_proxy.instance_variable_set(
        :@accepted_sxls,
        [{ 'name' => 'tlc', 'version' => RSMP::Schema.latest_version(:tlc) }]
      )
      site_proxy.instance_variable_set(:@sxl_interfaces, { 'tlc' => RejectingSxlInterface.new })

      result = site_proxy.process_packet({
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
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :message_rejected
    end

    it 'sends MessageNotAck when no accepted SXL defines an incoming message code' do
      protocol = ProxyHelper::CapturingProtocol.new
      site_proxy.instance_variable_set(:@protocol, protocol)
      site_proxy.instance_variable_set(:@state, :ready)
      site_proxy.instance_variable_set(:@core_version, '3.3.0')
      site_proxy.instance_variable_set(:@version_determined, true)
      site_proxy.instance_variable_set(
        :@accepted_sxls,
        [{ 'name' => 'tlc', 'version' => RSMP::Schema.latest_version(:tlc) }]
      )

      result = site_proxy.process_packet({
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
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :invalid_peer_message
    end

    it 'reports schema-valid messages for unknown components as peer failures' do
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'TLC001',
          'supervisors' => [],
          'sxls' => { 'tlc' => RSMP::Schema.latest_version(:tlc) }
        },
        log_settings: { 'active' => false }
      )
      protocol = ProxyHelper::CapturingProtocol.new
      supervisor_proxy = RSMP::SupervisorProxy.new(
        site: site,
        ip: '127.0.0.1',
        port: 12_345,
        protocol: protocol
      )
      supervisor_proxy.instance_variable_set(:@state, :ready)
      supervisor_proxy.instance_variable_set(:@core_version, '3.3.0')
      supervisor_proxy.instance_variable_set(:@version_determined, true)
      supervisor_proxy.instance_variable_set(
        :@accepted_sxls,
        [{ 'name' => 'tlc', 'version' => RSMP::Schema.latest_version(:tlc) }]
      )
      interface = CapturingSxlInterface.new
      interface.define_singleton_method(:process_message) do |_message|
        raise RSMP::UnknownComponent, 'Component unknown is missing'
      end
      supervisor_proxy.instance_variable_set(:@sxl_interfaces, { 'tlc' => interface })

      result = supervisor_proxy.process_packet({
        'mType' => 'rSMsg',
        'type' => 'StatusRequest',
        'cId' => 'unknown',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus' }],
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda'
      }.to_json)

      response = JSON.parse(protocol.lines.last)
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :invalid_peer_message
      expect(result.failure.source).to be == :peer
      expect(response['type']).to be == 'MessageNotAck'
      expect(response['rea']).to be =~ /Component unknown/
    end

    it 'does not relabel an implementation defect as a peer failure' do
      site_proxy.instance_variable_set(:@state, :ready)
      site_proxy.instance_variable_set(:@core_version, '3.3.0')
      site_proxy.instance_variable_set(:@version_determined, true)
      site_proxy.instance_variable_set(
        :@accepted_sxls,
        [{ 'name' => 'tlc', 'version' => RSMP::Schema.latest_version(:tlc) }]
      )
      site_proxy.instance_variable_set(:@sxl_interfaces, { 'tlc' => FaultySxlInterface.new })

      json = {
        'mType' => 'rSMsg',
        'type' => 'StatusUpdate',
        'cId' => 'C1',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => '1', 'q' => 'recent' }],
        'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda'
      }.to_json

      expect { site_proxy.process_packet(json) }.to raise_exception(
        NoMethodError,
        message: be =~ /unexpected_interface_bug/
      )
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
      supervisor_proxy.instance_variable_set(:@state, :ready)
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
      supervisor_proxy.instance_variable_set(:@state, :ready)
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
      site = build_site(core_version: '3.3.0', 'site_id' => 'TLC001', 'sxls' => { 'tlc' => '1.3.0' },
                        'components' => { 'device' => { 'C1' => {} } })
      protocol = ProxyHelper::CapturingProtocol.new
      proxy = build_supervisor_proxy(site, core_version: '3.3.0', protocol: protocol,
                                           accepted_sxls: [{ 'name' => 'tlc', 'version' => '1.3.0' }])
      [proxy, protocol]
    end

    def build_core_3_3_site_proxy
      protocol = ProxyHelper::CapturingProtocol.new
      proxy = build_site_proxy(core_version: '3.3.0', protocol: protocol,
                               settings: { 'sxls' => { 'tlc' => '1.3.0' }, 'core_version' => '3.3.0' },
                               accepted_sxls: [{ 'name' => 'tlc', 'version' => '1.3.0' }])
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

    it 'returns invalid caller messages as failures but raises for invalid generated messages' do
      proxy, = build_core_3_3_supervisor_proxy
      message = RSMP::MessageAck.new

      result = proxy.send_message message

      expect(result.failure?).to be == true
      expect(result.failure.source).to be == :local
      expect do
        proxy.send_generated_message message
      end.to raise_exception(RSMP::OperationError, message: be =~ /Could not send MessageAck/)
    end

    it 'does not relabel a receiver system error as a transport failure' do
      proxy, = build_core_3_3_supervisor_proxy
      receiver = Object.new
      receiver.define_singleton_method(:receive) do |_message|
        raise Errno::ENOENT, 'receiver defect'
      end
      proxy.add_receiver(receiver)

      expect do
        proxy.send_message(RSMP::Watchdog.new('wTs' => '2024-01-01T10:00:00.000Z'), validate: false)
      end.to raise_exception(Errno::ENOENT, message: be =~ /receiver defect/)
    end

    it 'sends empty deprecated NTS attributes for 3.3.0 messages' do
      proxy, = build_core_3_3_supervisor_proxy
      message = RSMP::StatusRequest.new

      proxy.apply_nts_message_attributes message

      expect(message.attributes['ntsOId']).to be == ''
      expect(message.attributes['xNId']).to be == ''
    end
  end

  with 'finite request operations' do
    def ready_site_proxy(protocol)
      build_site_proxy(core_version: '3.3.0', protocol: protocol,
                       settings: { 'sxls' => { 'tlc' => '1.3.0' }, 'core_version' => '3.3.0' },
                       accepted_sxls: [{ 'name' => 'tlc', 'version' => '1.3.0' }])
    end

    it 'returns the sent high-level message in a successful Result' do
      result = ready_site_proxy(ProxyHelper::CapturingProtocol.new).send_command(
        [{ 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'status', 'v' => 'NormalControl' }],
        component: 'C1',
        validate: false
      )

      expect(result.success?).to be == true
      expect(result.value).to be_a(RSMP::CommandRequest)
    end

    it 'starts collection before sending and returns an immutable Exchange' do
      proxy = nil
      protocol = ProxyHelper::CapturingProtocol.new do |_line|
        response = RSMP::CommandResponse.new(
          'cId' => 'C1',
          'cTS' => '2024-01-01T10:00:00.000Z',
          'rvs' => [{ 'cCI' => 'M0001', 'n' => 'status', 'v' => 'NormalControl', 'age' => 'recent' }]
        )
        response.direction = :in
        proxy.distribute(response)
      end
      proxy = ready_site_proxy(protocol)

      result = proxy.send_command_and_collect(
        [{ 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'status', 'v' => 'NormalControl' }],
        component: 'C1',
        within: 0.1,
        validate: false
      )

      expect(result.success?).to be == true
      expect(result.value).to be_a(RSMP::Exchange)
      expect(result.value.collection.messages.first).to be_a(RSMP::CommandResponse)
      expect(result.value.collection.frozen?).to be == true
    end
  end

  with 'message buffering' do
    def build_buffering_proxy(message_buffer: {}, core_version: '3.2.2')
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
      build_supervisor_proxy(site, core_version: core_version, state: :disconnected,
                                   protocol: nil, version_determined: false)
    end

    it 'buffers site-originated aggregated status while disconnected' do
      proxy = build_buffering_proxy
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
      proxy = build_buffering_proxy(core_version: nil)
      component = RSMP::Component.new(id: 'C1', node: proxy.site, grouped: true)

      proxy.send_aggregated_status component

      expect(proxy.message_buffer.size).to be == 1
      expect(proxy.message_buffer.first.attributes['se']).to be == [false, false, false, false, false, true, false, false]
    end

    it 'does not buffer command messages while disconnected' do
      proxy = build_buffering_proxy
      message = RSMP::CommandResponse.new(
        'cId' => 'C1',
        'cTS' => '2024-01-01T10:00:00.000Z',
        'cCI' => 'M0001',
        'n' => 'status',
        'age' => 'recent',
        'rvs' => [{ 'n' => 'status', 'v' => 'true' }]
      )

      result = proxy.send_message message
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :not_ready
      expect(proxy.message_buffer).to be == []
    end

    it 'filters buffered status updates by configured selector' do
      proxy = build_buffering_proxy(
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
      proxy = build_buffering_proxy(
        message_buffer: { 'statuses' => true },
        core_version: '3.1.5'
      )
      proxy.send_message RSMP::StatusUpdate.new(
        'cId' => 'C1',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => '1', 'q' => 'recent' }]
      )

      protocol = ProxyHelper::CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.instance_variable_set(:@core_version, '3.2.2')
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['sS']).to be == [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => '1', 'q' => 'old' }]
      expect(proxy.message_buffer).to be == []
    end

    it 'preserves buffered status update timestamps when flushing' do
      proxy = build_buffering_proxy(message_buffer: { 'statuses' => true })
      proxy.send_message RSMP::StatusUpdate.new(
        'cId' => 'C1',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => '1', 'q' => 'recent' }]
      )

      protocol = ProxyHelper::CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['sTs']).to be == '2024-01-01T10:00:00.000Z'
    end

    it 'uses the reconnect core version when flushing buffered aggregated status' do
      proxy = build_buffering_proxy(core_version: '3.1.2')
      proxy.send_message RSMP::AggregatedStatus.new(
        'cId' => 'C1',
        'aSTS' => '2024-01-01T10:00:00.000Z',
        'fP' => nil,
        'fS' => nil,
        'se' => %w[false false false false false true false false]
      )

      protocol = ProxyHelper::CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.instance_variable_set(:@core_version, '3.2.2')
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['se']).to be == [false, false, false, false, false, true, false, false]
    end

    it 'preserves buffered aggregated status timestamps when flushing' do
      proxy = build_buffering_proxy
      proxy.send_message RSMP::AggregatedStatus.new(
        'cId' => 'C1',
        'aSTS' => '2024-01-01T10:00:00.000Z',
        'fP' => nil,
        'fS' => nil,
        'se' => [false, false, false, false, false, true, false, false]
      )

      protocol = ProxyHelper::CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['aSTS']).to be == '2024-01-01T10:00:00.000Z'
    end

    it 'preserves buffered alarm timestamps when flushing' do
      proxy = build_buffering_proxy
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

      protocol = ProxyHelper::CapturingProtocol.new
      proxy.instance_variable_set(:@protocol, protocol)
      proxy.instance_variable_set(:@state, :connected)
      proxy.flush_message_buffer

      sent = JSON.parse(protocol.lines.last)
      expect(sent['aTs']).to be == '2024-01-01T10:00:00.000Z'
    end

    it 'drops the oldest buffered message when the buffer is full' do
      proxy = build_buffering_proxy(message_buffer: { 'max_messages' => 1 })

      first = RSMP::AlarmIssue.new('cId' => 'C1', 'aCId' => 'A1')
      second = RSMP::AlarmIssue.new('cId' => 'C1', 'aCId' => 'A2')
      proxy.send_message first
      proxy.send_message second

      expect(proxy.message_buffer.size).to be == 1
      expect(proxy.message_buffer.first.attributes['aCId']).to be == 'A2'
    end

    it 'prunes subscriptions that are not configured for buffering' do
      proxy = build_buffering_proxy(
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

  with 'Core 3.3.0 version negotiation' do
    let(:core_version) { '3.3.0' }
    let(:site) do
      build_site(core_version: core_version, 'sxls' => { 'tlc' => '1.3.0' },
                 'components' => { 'device' => { 'a' => {}, 'b' => {} } })
    end

    def version_response(sxls)
      RSMP::Version.new('step' => 'Response', 'RSMP' => [{ 'vers' => core_version }],
                        'supervisorId' => 'informational', 'SXLS' => sxls)
    end

    it 'closes invalid Version responses and only rejects valid received message IDs' do
      [nil, 'invalid', RSMP::Message.make_m_id].each do |id|
        proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
        proxy.instance_variable_set(:@version_determined, false)
        proxy.instance_variable_set(:@session_closed, false)
        packet = version_response([]).attributes.merge('mId' => id, 'RSMP' => [])
        packet.delete('mId') unless id
        expect(proxy.process_packet(JSON.generate(packet)).failure?).to be == true
        expect(proxy.disconnected?).to be == true
        expected = id && id != 'invalid' ? ['MessageNotAck'] : []
        expect(messages(proxy).map { |message| message['type'] }).to be == expected
      end
    end

    it 'does not treat a response version outside the original offer as a match' do
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      proxy.instance_variable_set(:@offered_core_versions, ['3.2.2'])
      expect { proxy.check_core_version(version_response([])) }.to raise_exception(RSMP::HandshakeError)
    end

    it 'accepts nonfatal SXL statuses and never falls back to supported versions' do
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      response = version_response([
                                    { 'name' => 'tlc', 'status' => 'mismatch', 'supported' => ['1.2.1'] },
                                    { 'name' => 'vms', 'status' => 'expected' }
                                  ])
      proxy.validate_version!(response, step: 'Response')
      proxy.check_sxl_version(response)
      expect(proxy.accepted_sxls).to be == []
      expect(proxy.rejected_sxls).to be == response.sxls
      expect(proxy.use_alarms?).to be == true
    end

    it 'rejects duplicate, missing and unsolicited accepted SXLs' do
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      ok = { 'name' => 'tlc', 'status' => 'ok', 'version' => '1.3.0' }
      expect do
        proxy.validate_version!(version_response([ok, ok]), step: 'Response')
      end.to raise_exception(RSMP::HandshakeError)
      [[], [ok.merge('name' => 'vms')], [ok.merge('version' => '1.2.1')]].each do |items|
        expect { proxy.check_sxl_version(version_response(items)) }.to raise_exception(RSMP::HandshakeError)
      end
    end
  end

  with 'Core 3.3.0 buffered messages' do
    let(:core_version) { '3.3.0' }
    let(:site) do
      build_site(core_version: core_version, 'sxls' => { 'tlc' => '1.3.0' },
                 'components' => { 'device' => { 'a' => {}, 'b' => {} } })
    end

    it 'skips rejected-SXL buffered traffic without blocking later core messages' do
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      proxy.instance_variable_set(:@accepted_sxls, [])
      update = RSMP::StatusUpdate.new('cId' => 'a', 'sTs' => RSMP::Clock.to_s,
                                      'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus',
                                                 's' => 'R', 'q' => 'recent' }])
      status = RSMP::AggregatedStatus.new('aSTS' => RSMP::Clock.to_s, 'se' => Array.new(8, false))
      proxy.message_buffer.push(update, status)
      proxy.flush_message_buffer
      expect(messages(proxy).map { |message| message['type'] }).to be == ['AggregatedStatus']
      expect(proxy.message_buffer).to be == []
    end
  end
end
