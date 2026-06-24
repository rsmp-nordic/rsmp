require_relative '../support/async_helper'

describe RSMP::Site do
  class SiteCapturingProtocol
    attr_reader :lines

    def initialize
      @lines = []
    end

    def write_lines(line)
      @lines << line
    end
  end

  let(:collect_timeout) { 1 }

  let(:ip) { 'localhost' }
  let(:port) { 13_111 }
  let(:site_settings) do
    {
      'site_id' => 'RN+SI0001',
      'supervisors' => [
        { 'ip' => ip, 'port' => port }
      ]
    }
  end

  let(:log_settings) do
    {
      'active' => false,
      'watchdogs' => true,
      'acknowledgements' => true
    }
  end

  with '#initialize' do
    it 'accepts no options' do
      expect { subject.new({}) }.not.to raise_exception
    end

    it 'accepts options' do
      expect do
        subject.new(
          site_settings: site_settings,
          log_settings: log_settings
        )
      end.not.to raise_exception
    end
  end

  with 'connection handshake' do
    it 'completes' do
      # mock SecureRandom.uuid() so we get known message ids
      uuids = %w[
        1b206e56-31be-4739-9164-3a24d47b0aa2
        fd92d6f6-f0c3-4a91-a582-6fff4e5bb63b
        1e363b78-a67a-40f0-a2b1-acb231656594
        51931724-b143-45a3-aa43-171f79ebb337
        d5ccbf4b-e951-4476-bf23-8aa8f6835fb5
        3942bc2b-c0dc-45be-b3bf-b25e3afa300f
        0459805f-73aa-41b1-beed-11852f62756d
        16ec49e4-6ac1-4da6-827c-2a6562b91731
      ].each
      mock(SecureRandom).replace(:uuid) { uuids.next }

      site = subject.new(
        site_settings: site_settings,
        log_settings: log_settings
      )

      with_async_context(context: lambda {
        # acts as a supervisor by listening for connections
        # and exchanging RSMP handshake
        endpoint = IO::Endpoint.tcp('localhost', port)
        endpoint.accept do |socket, _address|
          stream = IO::Stream::Buffered.new(socket)
          protocol = RSMP::Protocol.new(stream)

          # read version
          message = JSON.parse protocol.read_line
          core_versions = RSMP::Schema.core_versions
          core_versions_array = core_versions.map { |version| { 'vers' => version } }
          sxl_version = site.sxl_version
          expect(message['mType']).to be == 'rSMsg'
          expect(message['type']).to be == 'Version'
          expect(message['step']).to be == 'Request'
          expect(message['siteId']).to be == [{ 'sId' => 'RN+SI0001' }]
          expect(message['RSMP']).to be == core_versions_array
          expect(message['SXL']).to be == sxl_version
          expect(message['SXLS']).to be == [{ 'name' => 'tlc', 'version' => sxl_version }]

          # send version ack
          protocol.write_lines JSON.generate('mType' => 'rSMsg', 'type' => 'MessageAck', 'oMId' => message['mId'])

          # write version response
          protocol.write_lines({
            'mType' => 'rSMsg',
            'type' => 'Version',
            'step' => 'Response',
            'RSMP' => [{ 'vers' => core_versions.last }],
            'supervisorId' => 'SUPERVISOR',
            'SXLS' => [{ 'name' => 'tlc', 'version' => sxl_version }],
            'receiveAlarms' => true,
            'mId' => '51931724-b143-45a3-aa43-171f79ebb337'
          }.to_json)

          # read version ack
          message = JSON.parse protocol.read_line
          expect(message['mType']).to be == 'rSMsg'
          expect(message['type']).to be == 'MessageAck'
          expect(message['mId']).to be_nil

          # read watchdog
          message = JSON.parse protocol.read_line
          expect(message['mType']).to be == 'rSMsg'
          expect(message['type']).to be == 'Watchdog'

          # send watchdog ack
          protocol.write_lines %({"mType":"rSMsg","type":"MessageAck","oMId":"#{message['mId']}"})

          # send watchdog
          protocol.write_lines %({"mType":"rSMsg","type":"Watchdog","wTs":"2022-09-08T13:10:24.695Z","mId":"439e5748-0662-4ab2-a0d7-80fc680f04f5"})

          # read watchdog ack
          message = JSON.parse protocol.read_line
          expect(message['mType']).to be == 'rSMsg'
          expect(message['type']).to be == 'MessageAck'

          # read component list
          message = JSON.parse protocol.read_line
          expect(message['mType']).to be == 'rSMsg'
          expect(message['type']).to be == 'ComponentList'
          expect(message['components']).to be == [{ 'id' => 'C1', 'type' => 'main', 'name' => 'C1' }]

          # send component list ack
          protocol.write_lines JSON.generate('mType' => 'rSMsg', 'type' => 'MessageAck', 'oMId' => message['mId'])
        end
      }) do |_task|
        site.start
        proxy = site.wait_for_supervisor :any, timeout: collect_timeout
        expect(proxy).to be_a(RSMP::SupervisorProxy)
        proxy.wait_for_state(:ready, timeout: collect_timeout)
      end
    end
  end

  with '#send_alarm' do
    it 'does not send unsolicited alarms to supervisors that opted out' do
      site = subject.new(
        site_settings: site_settings,
        log_settings: log_settings
      )
      sent = []
      proxy = Object.new
      proxy.define_singleton_method(:ready?) { true }
      proxy.define_singleton_method(:receive_alarms?) { false }
      proxy.define_singleton_method(:send_message) { |message| sent << message }
      site.instance_variable_set(:@proxies, [proxy])

      site.send_alarm RSMP::AlarmIssue.new

      expect(sent).to be == []
    end
  end

  with 'message buffering with multiple supervisors' do
    def build_buffering_site
      subject.new(
        site_settings: {
          'site_id' => 'TLC001',
          'supervisors' => [],
          'sxls' => { 'tlc' => '1.2.1' },
          'message_buffer' => {
            'enabled' => true,
            'max_messages' => 10_000,
            'statuses' => true
          }
        },
        log_settings: { 'active' => false }
      )
    end

    def build_site_supervisor_proxy(site, port:, state:, protocol: nil)
      proxy = RSMP::SupervisorProxy.new(
        site: site,
        ip: '127.0.0.1',
        port: port
      )
      proxy.instance_variable_set(:@core_version, '3.2.2')
      proxy.instance_variable_set(:@accepted_sxls, [{ 'name' => 'tlc', 'version' => '1.2.1' }])
      proxy.instance_variable_set(:@state, state)
      proxy.instance_variable_set(:@protocol, protocol) if protocol
      proxy
    end

    it 'sends aggregated status to connected supervisors and buffers it for disconnected supervisors' do
      site = build_buffering_site
      protocol = SiteCapturingProtocol.new
      connected = build_site_supervisor_proxy(site, port: 12_345, state: :connected, protocol: protocol)
      disconnected = build_site_supervisor_proxy(site, port: 12_346, state: :disconnected)
      site.instance_variable_set(:@proxies, [connected, disconnected])
      component = RSMP::Component.new(node: site, id: 'C1', grouped: true)

      site.aggregated_status_changed component

      sent = JSON.parse(protocol.lines.first)
      expect(sent['type']).to be == 'AggregatedStatus'
      expect(connected.message_buffer).to be == []
      expect(disconnected.message_buffer.size).to be == 1
      expect(disconnected.message_buffer.first).to be_a(RSMP::AggregatedStatus)
    end

    it 'sends alarms to connected supervisors and buffers them for disconnected supervisors' do
      site = build_buffering_site
      protocol = SiteCapturingProtocol.new
      connected = build_site_supervisor_proxy(site, port: 12_345, state: :connected, protocol: protocol)
      disconnected = build_site_supervisor_proxy(site, port: 12_346, state: :disconnected)
      site.instance_variable_set(:@proxies, [connected, disconnected])
      alarm = RSMP::AlarmIssue.new(
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

      site.send_alarm alarm

      sent = JSON.parse(protocol.lines.first)
      expect(sent['type']).to be == 'Alarm'
      expect(sent['aCId']).to be == 'A0001'
      expect(connected.message_buffer).to be == []
      expect(disconnected.message_buffer.size).to be == 1
      expect(disconnected.message_buffer.first).to be_a(RSMP::AlarmIssue)
    end
  end

  with '#tick_status_subscriptions' do
    it 'ticks supervisor proxies even when they are not ready' do
      site = subject.new(
        site_settings: site_settings,
        log_settings: log_settings
      )
      now = Time.now
      ticks = []
      proxy = Object.new
      proxy.define_singleton_method(:status_update_timer) { |time| ticks << time }
      site.instance_variable_set(:@proxies, [proxy])

      site.tick_status_subscriptions now

      expect(ticks).to be == [now]
    end
  end
end
