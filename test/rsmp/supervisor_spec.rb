require_relative '../support/async_helper'

describe RSMP::Supervisor do
  let(:collect_timeout) { 1 }

  let(:supervisor_settings) do
    {
      'port' => 13_111,
      'default' => {
        'sxl' => 'tlc'
      }
    }
  end

  let(:log_settings) do
    {
      'active' => false,
      'hide_ip_and_port' => true,
      'debug' => false,
      'json' => true,
      'acknowledgements' => true,
      'watchdogs' => false
    }
  end

  with '#initialize' do
    it 'accepts no options' do
      expect { subject.new({}) }.not.to raise_exception
    end

    it 'accepts options' do
      expect do
        subject.new(
          supervisor_settings: supervisor_settings,
          log_settings: log_settings
        )
      end.not.to raise_exception
    end
  end

  with 'connection handshake' do
    let(:supervisor) do
      subject.new(
        supervisor_settings: supervisor_settings,
        log_settings: log_settings
      )
    end

    def site_connect
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

      endpoint = IO::Endpoint.tcp('127.0.0.1', supervisor.supervisor_settings['port'])
      supervisor.ready_condition.wait
      socket = endpoint.connect
      stream = IO::Stream::Buffered.new(socket)
      RSMP::Protocol.new(stream)
    end

    def handshake(protocol, core_versions:, sxl_version:)
      core_versions_array = core_versions.map { |version| { 'vers' => version } }

      send_version_message(protocol, core_versions_array, sxl_version)
      receive_version_ack(protocol)
      receive_version_message(protocol, core_versions_array, sxl_version)
      send_version_ack(protocol)
      perform_watchdog_handshake(protocol)
      wait_for_proxy_creation
    end

    def send_version_message(protocol, core_versions_array, sxl_version)
      protocol.write_lines %({"mType":"rSMsg","type":"Version","RSMP":#{core_versions_array.to_json},"siteId":[{"sId":"RN+SI0001"}],"SXL":#{sxl_version.to_json},"mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6"})
    end

    def receive_version_ack(protocol)
      version_ack = JSON.parse protocol.read_line
      expect(version_ack['mType']).to be == 'rSMsg'
      expect(version_ack['type']).to be == 'MessageAck'
      expect(version_ack['oMId']).to be == '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6'
      expect(version_ack['mId']).to be_nil
    end

    def receive_version_message(protocol, core_versions_array, sxl_version)
      version = JSON.parse protocol.read_line
      expect(version).to be == ({ 'RSMP' => core_versions_array, 'SXL' => sxl_version,
                                  'mId' => '1b206e56-31be-4739-9164-3a24d47b0aa2', 'mType' => 'rSMsg', 'siteId' => [{ 'sId' => 'RN+SI0001' }], 'type' => 'Version' })
    end

    def send_version_ack(protocol)
      protocol.write_lines JSON.generate('mType' => 'rSMsg', 'type' => 'MessageAck', 'oMId' => '1b206e56-31be-4739-9164-3a24d47b0aa2',
                                         'mId' => SecureRandom.uuid)
    end

    def perform_watchdog_handshake(protocol)
      # send watchdog
      protocol.write_lines %({"mType":"rSMsg","type":"Watchdog","wTs":"2022-09-08T13:10:24.695Z","mId":"439e5748-0662-4ab2-a0d7-80fc680f04f5"})

      # read watchdog ack
      JSON.parse protocol.read_line

      # read watchdog
      JSON.parse protocol.read_line

      # send watchdog ack
      protocol.write_lines %({"mType":"rSMsg","type":"MessageAck","oMId":"1e363b78-a67a-40f0-a2b1-acb231656594"})
    end

    def wait_for_proxy_creation
      proxy = supervisor.wait_for_site 'RN+SI0001', timeout: collect_timeout
      proxy.wait_for_state(:ready, timeout: collect_timeout)
      proxy
    end

    it 'completes' do
      with_async_context(context: lambda {
        supervisor.start
      }) do |_task|
        core_versions = RSMP::Schema.core_versions
        sxl_version = RSMP::Schema.latest_version(:tlc)
        protocol = site_connect
        proxy = handshake(protocol, core_versions: core_versions, sxl_version: sxl_version)

        expect(proxy).to be_a(RSMP::SiteProxy)
        expect(proxy.site_id).to be == 'RN+SI0001'
      end
    end

    it 'logs' do
      with_async_context(context: lambda {
        supervisor.start
      }) do |_task|
        core_versions = RSMP::Schema.core_versions
        sxl_version = RSMP::Schema.latest_version(:tlc)
        protocol = site_connect
        handshake(protocol, core_versions: core_versions, sxl_version: sxl_version)

        # verify log content
        got = supervisor.archive.by_level(%i[log info]).map { |item| item[:text] }
        expected = [
          'Starting supervisor on port 13111',
          'Site connected from ********',
          'Received Version message for site RN+SI0001',
          'Sent MessageAck for Version 8db0',
          'Sent Version',
          'Received MessageAck for Version 1b20',
          'Received Watchdog',
          'Sent MessageAck for Watchdog 439e',
          'Sent Watchdog',
          'Received MessageAck for Watchdog 1e36',
          "Connection to site RN+SI0001 established, using core #{core_versions.last}, tlc #{sxl_version}"
        ]
        expect(got.sort).to be == expected.sort
      end
    end

    it 'validates initial messages with correct core version' do
      with_async_context(context: lambda {
        supervisor.start
      }) do |_task|
        core_version = '3.1.3'
        sxl_version = RSMP::Schema.latest_version(:tlc).to_s

        protocol = site_connect
        protocol.write_lines %({"mType":"rSMsg","type":"Version","RSMP":[{"vers":"#{core_version}"}],"siteId":[{"sId":"RN+SI0001"}],"SXL":"#{sxl_version}","mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6"})

        proxy = supervisor.wait_for_site 'RN+SI0001', timeout: collect_timeout
        expect(proxy).to be_a(RSMP::SiteProxy)
        expect(proxy.site_id).to be == 'RN+SI0001'

        expect(proxy.core_version).to be == core_version
      end
    end

    it 'accepts a 2-part sxl version like "1.2" and echoes it back unchanged' do
      with_async_context(context: lambda {
        supervisor.start
      }) do |_task|
        core_versions = RSMP::Schema.core_versions
        sxl_version = '1.2'
        protocol = site_connect
        proxy = handshake(protocol, core_versions: core_versions, sxl_version: sxl_version)

        expect(proxy).to be_a(RSMP::SiteProxy)
        expect(proxy.state).to be == :ready
      end
    end

    it 'accepts a 3-part sxl version like "1.2.1" and echoes it back unchanged' do
      with_async_context(context: lambda {
        supervisor.start
      }) do |_task|
        core_versions = RSMP::Schema.core_versions
        sxl_version = '1.2.1'
        protocol = site_connect
        proxy = handshake(protocol, core_versions: core_versions, sxl_version: sxl_version)

        expect(proxy).to be_a(RSMP::SiteProxy)
        expect(proxy.state).to be == :ready
      end
    end
  end
end
