require_relative '../support/async_helper'

describe RSMP::Site do
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
          expect(message['siteId']).to be == [{ 'sId' => 'RN+SI0001' }]
          expect(message['RSMP']).to be == core_versions_array
          expect(message['SXL']).to be == sxl_version

          # send version ack
          protocol.write_lines JSON.generate('mType' => 'rSMsg', 'type' => 'MessageAck', 'oMId' => message['mId'])

          # write version message
          protocol.write_lines %({"mType":"rSMsg","type":"Version","RSMP":[{"vers":"#{core_versions.last}"}],"siteId":[{"sId":"RN+SI0001"}],"SXL":"#{sxl_version}","mId":"51931724-b143-45a3-aa43-171f79ebb337"})

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
          JSON.parse protocol.read_line
        end
      }) do |_task|
        site.start
        proxy = site.wait_for_supervisor :any, timeout: collect_timeout
        expect(proxy).to be_a(RSMP::SupervisorProxy)
        proxy.wait_for_state(:ready, timeout: collect_timeout)
      end
    end
  end
end
