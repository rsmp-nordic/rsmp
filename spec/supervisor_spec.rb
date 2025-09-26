RSpec.describe RSMP::Supervisor do
  let(:timeout) { 1 }

  let(:supervisor_settings) do
    {
      'port' => 13_111, # use special port to avoid sites connection during test
      'guest' => {
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

  describe '#initialize' do
    it 'accepts no options' do
      expect { RSMP::Supervisor.new({}) }.not_to raise_error
    end

    it 'accepts options' do
      RSMP::Supervisor.new(
        supervisor_settings: supervisor_settings,
        log_settings: log_settings
      )
    end
  end

  describe 'connection handshake' do
    let(:supervisor) do
      RSMP::Supervisor.new(
        supervisor_settings: supervisor_settings,
        log_settings: log_settings
      )
    end

    def site_connect(_task)
      # mock SecureRandom.uui() so we get known message ids:
      allow(SecureRandom).to receive(:uuid).and_return(
        '1b206e56-31be-4739-9164-3a24d47b0aa2',
        'fd92d6f6-f0c3-4a91-a582-6fff4e5bb63b',
        '1e363b78-a67a-40f0-a2b1-acb231656594',
        '51931724-b143-45a3-aa43-171f79ebb337',
        'd5ccbf4b-e951-4476-bf23-8aa8f6835fb5',
        '3942bc2b-c0dc-45be-b3bf-b25e3afa300f',
        '0459805f-73aa-41b1-beed-11852f62756d',
        '16ec49e4-6ac1-4da6-827c-2a6562b91731'
      )

      endpoint = IO::Endpoint.tcp('127.0.0.1', supervisor.supervisor_settings['port'])
      supervisor.ready_condition.wait
      socket = endpoint.connect
      stream = IO::Stream::Buffered.new(socket)
      RSMP::Protocol.new(stream)
    end

    VERSION_MESSAGE_ID = '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6'.freeze
    WATCHDOG_MESSAGE_ID = '439e5748-0662-4ab2-a0d7-80fc680f04f5'.freeze
    WATCHDOG_TIMESTAMP = '2022-09-08T13:10:24.695Z'.freeze

    def handshake(protocol, core_versions:, sxl_version:)
      versions = build_core_versions(core_versions)
      send_version_message(protocol, versions, sxl_version)
      expect_version_ack(protocol)
      version = expect_supervisor_version(protocol, versions, sxl_version)
      acknowledge_version(protocol, version['mId'])
      exchange_watchdogs(protocol)
      wait_for_ready_site
    end

    def build_core_versions(core_versions)
      core_versions.map { |version| { 'vers' => version } }
    end

    def send_version_message(protocol, versions, sxl_version)
      protocol.write_lines version_message_json(versions, sxl_version)
    end

    def version_message_json(versions, sxl_version)
      JSON.generate(
        'mType' => 'rSMsg',
        'type' => 'Version',
        'RSMP' => versions,
        'siteId' => [{ 'sId' => 'RN+SI0001' }],
        'SXL' => sxl_version,
        'mId' => VERSION_MESSAGE_ID
      )
    end

    def expect_version_ack(protocol)
      version_ack = JSON.parse protocol.read_line
      expect(version_ack['mType']).to eq('rSMsg')
      expect(version_ack['type']).to eq('MessageAck')
      expect(version_ack['oMId']).to eq(VERSION_MESSAGE_ID)
      expect(version_ack['mId']).to be_nil
    end

    def expect_supervisor_version(protocol, versions, sxl_version)
      expected = {
        'RSMP' => versions,
        'SXL' => sxl_version,
        'mId' => '1b206e56-31be-4739-9164-3a24d47b0aa2',
        'mType' => 'rSMsg',
        'siteId' => [{ 'sId' => 'RN+SI0001' }],
        'type' => 'Version'
      }

      version = JSON.parse protocol.read_line
      expect(version).to eq(expected)
      version
    end

    def acknowledge_version(protocol, message_id)
      protocol.write_lines JSON.generate(
        'mType' => 'rSMsg',
        'type' => 'MessageAck',
        'oMId' => message_id,
        'mId' => SecureRandom.uuid
      )
    end

    def exchange_watchdogs(protocol)
      send_watchdog_message(protocol)
      expect_watchdog_ack(protocol)
      watchdog = expect_watchdog_message(protocol)
      acknowledge_watchdog(protocol, watchdog['mId'])
    end

    def send_watchdog_message(protocol)
      protocol.write_lines JSON.generate(
        'mType' => 'rSMsg',
        'type' => 'Watchdog',
        'wTs' => WATCHDOG_TIMESTAMP,
        'mId' => WATCHDOG_MESSAGE_ID
      )
    end

    def expect_watchdog_ack(protocol)
      ack = JSON.parse protocol.read_line
      expect(ack['type']).to eq('MessageAck')
      expect(ack['oMId']).to eq(WATCHDOG_MESSAGE_ID)
    end

    def expect_watchdog_message(protocol)
      watchdog = JSON.parse protocol.read_line
      expect(watchdog['type']).to eq('Watchdog')
      watchdog
    end

    def acknowledge_watchdog(protocol, message_id)
      protocol.write_lines JSON.generate(
        'mType' => 'rSMsg',
        'type' => 'MessageAck',
        'oMId' => message_id
      )
    end

    def wait_for_ready_site
      proxy = supervisor.wait_for_site 'RN+SI0001', timeout: timeout
      proxy.wait_for_state(:ready, timeout: timeout)
      proxy
    end

    it 'completes' do
      AsyncRSpec.async context: lambda {
        supervisor.start
      } do |task|
        core_versions = RSMP::Schema.core_versions
        sxl_version = RSMP::Schema.latest_version(:tlc)
        protocol = site_connect task
        proxy = handshake(protocol, core_versions: core_versions, sxl_version: sxl_version)

        expect(proxy).to be_an(RSMP::SiteProxy)
        expect(proxy.site_id).to eq('RN+SI0001')
      end
    end

    it 'logs' do
      AsyncRSpec.async context: lambda {
        supervisor.start
      } do |task|
        core_versions = RSMP::Schema.core_versions
        sxl_version = RSMP::Schema.latest_version(:tlc)
        protocol = site_connect task
        handshake(protocol, core_versions: core_versions, sxl_version: sxl_version)

        # verify log content
        got = supervisor.archive.by_level(%i[log info]).map { |item| item[:text] }
        expect(got).to match_array([
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
                                   ])
      end
    end

    it 'validates initial messages with correct core version' do
      AsyncRSpec.async context: lambda {
        supervisor.start
      } do |task|
        # write version message
        core_version = '3.1.3'
        sxl_version = RSMP::Schema.latest_version(:tlc).to_s

        protocol = site_connect task
        protocol.write_lines %({"mType":"rSMsg","type":"Version","RSMP":[{"vers":"#{core_version}"}],"siteId":[{"sId":"RN+SI0001"}],"SXL":"#{sxl_version}","mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6"})

        # wait for site to connect
        proxy = supervisor.wait_for_site 'RN+SI0001', timeout: timeout
        expect(proxy).to be_an(RSMP::SiteProxy)
        expect(proxy.site_id).to eq('RN+SI0001')

        # check that supervisor have correctly determined the version
        expect(proxy.core_version).to eq(core_version)
      end
    end
  end
end
