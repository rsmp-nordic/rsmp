RSpec.describe RSMP::Supervisor do
  let(:timeout) { 1 }

  let(:supervisor_settings) {
    {
      'port' => 13111,    # use special port to avoid sites connection during test
      'guest' => {
        'sxl' => 'tlc'
      }
    }
  }

  let(:log_settings) {
    {
      'active' => false,
      'hide_ip_and_port' => true,
      'debug' => false,
      'json' => true,
      'acknowledgements' => true,
      'watchdogs' => false
    }
  }

  describe '#initialize' do
    it 'accepts no options' do
      expect { RSMP::Supervisor.new({}) }.not_to raise_error
    end

    it 'accepts options' do
      supervisor = RSMP::Supervisor.new(
        supervisor_settings: supervisor_settings,
        log_settings: log_settings
      )
    end
  end

  describe 'connection handshake' do
    let(:supervisor) {
      RSMP::Supervisor.new(
        supervisor_settings: supervisor_settings,
        log_settings: log_settings
      )
    }

    let(:endpoint) {
      Async::IO::Endpoint.tcp("127.0.0.1", supervisor.supervisor_settings['port'])
    }

    let(:socket) {
      endpoint.connect
    }

    let(:stream) {
      Async::IO::Stream.new(socket)
    }

    let(:protocol) {
      Async::IO::Protocol::Line.new(stream,RSMP::Proxy::WRAPPING_DELIMITER) # rsmp messages are json terminated with a form-feed
    }

    def connect task, core_versions:, sxl_version:
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

      # get core versions array
      core_versions_array = core_versions.map {|version| {"vers" => version} }

      # write version message
      protocol.write_lines %({"mType":"rSMsg","type":"Version","RSMP":#{core_versions_array.to_json},"siteId":[{"sId":"RN+SI0001"}],"SXL":#{sxl_version.to_json},"mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6"})

      # read version ack
      version_ack = JSON.parse protocol.read_line
      expect(version_ack['mType']).to eq('rSMsg')
      expect(version_ack['type']).to eq('MessageAck')
      expect(version_ack['oMId']).to eq('8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6')
      expect(version_ack['mId']).to be_nil

      # read version
      version = JSON.parse protocol.read_line
      expect(version).to eq({"RSMP"=>core_versions_array, "SXL"=>sxl_version, "mId"=>"1b206e56-31be-4739-9164-3a24d47b0aa2", "mType"=>"rSMsg", "siteId"=>[{"sId"=>"RN+SI0001"}], "type"=>"Version"})

      # send version ack
      protocol.write_lines JSON.generate("mType"=>"rSMsg","type"=>"MessageAck","oMId"=>version["mId"],"mId"=>SecureRandom.uuid())

      # send watchdog
      protocol.write_lines %/{"mType":"rSMsg","type":"Watchdog","wTs":"2022-09-08T13:10:24.695Z","mId":"439e5748-0662-4ab2-a0d7-80fc680f04f5"}/

      # read watchdog ack
      watchdog_ack = JSON.parse protocol.read_line

      # read watchdog
      watchdog = JSON.parse protocol.read_line

      # send watchdog ack
      protocol.write_lines %/{"mType":"rSMsg","type":"MessageAck","oMId":"1e363b78-a67a-40f0-a2b1-acb231656594"}/

      # supervisor should see our tcp socket and create a proxy
      proxy = supervisor.wait_for_site "RN+SI0001", timeout: timeout
      proxy.wait_for_state(:ready, timeout: timeout)
      proxy
    end

    it 'completes' do
      AsyncRSpec.async context: lambda { supervisor.start } do |task|
        core_versions = RSMP::Schema.core_versions
        sxl_version = RSMP::Schema.latest_version(:tlc)
        proxy = connect task, core_versions:core_versions, sxl_version:sxl_version

        expect(proxy).to be_an(RSMP::SiteProxy)
        expect(proxy.site_id).to eq("RN+SI0001")
      end
    end

    it 'logs' do
      AsyncRSpec.async context: lambda { supervisor.start } do |task|
        core_versions = RSMP::Schema.core_versions
        sxl_version = RSMP::Schema.latest_version(:tlc)
        proxy = connect task, core_versions:core_versions, sxl_version:sxl_version

        # verify log content
        got = supervisor.archive.by_level([:log, :info]).map { |item| item[:text] }
        expect( got ).to match_array([
          "Starting supervisor on port 13111",
           "Site connected from ********",
           "Received Version message for site RN+SI0001",
           "Sent MessageAck for Version 8db0",
           "Sent Version",
           "Received MessageAck for Version 1b20",
           "Received Watchdog",
           "Sent MessageAck for Watchdog 439e",
           "Sent Watchdog",
           "Received MessageAck for Watchdog 1e36",
           "Connection to site RN+SI0001 established, using core #{core_versions.last}, tlc #{sxl_version}"
        ])
      end
    end

    it 'validates initial messages with correct core version' do
      AsyncRSpec.async context: lambda { supervisor.start } do |task|
        # write version message
        core_version = '3.1.3'
        sxl_version = RSMP::Schema.latest_version(:tlc).to_s
        protocol.write_lines %/{"mType":"rSMsg","type":"Version","RSMP":[{"vers":"#{core_version}"}],"siteId":[{"sId":"RN+SI0001"}],"SXL":"#{sxl_version}","mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6"}/

        # wait for site to connect
        proxy = supervisor.wait_for_site "RN+SI0001", timeout: timeout
        expect(proxy).to be_an(RSMP::SiteProxy)
        expect(proxy.site_id).to eq("RN+SI0001")

        # check that supervisor have correctly determined the version
        expect( proxy.core_version ).to eq( core_version )
      end
    end
  end
end
