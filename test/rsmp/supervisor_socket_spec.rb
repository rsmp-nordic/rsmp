require_relative '../support/async_helper'

describe RSMP::Supervisor do
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

  with 'connection handshake' do
    let(:test_data) do
      core_versions = RSMP::Schema.core_versions
      {
        site_id: 'RN+SI0001',
        message_ids: {
          version_from_site: '1b206e56-31be-4739-9164-3a24d47b0aa2',
          watchdog_from_site: 'fd92d6f6-f0c3-4a91-a582-6fff4e5bb63b',
          version_from_supervisor: '51931724-b143-45a3-aa43-171f79ebb337',
          watchdog_from_supervisor: '439e5748-0662-4ab2-a0d7-80fc680f04f5'
        },
        watchdog_timestamp: '2022-09-08T13:10:24.695Z',
        core_versions: core_versions,
        core_versions_array: core_versions.map { |version| { 'vers' => version } },
        sxl_version: RSMP::Schema.latest_version(:tlc)
      }
    end

    def send_message_ack(protocol, original_id)
      protocol.write_lines JSON.generate('mType' => 'rSMsg', 'type' => 'MessageAck', 'oMId' => original_id)
    end

    def send_version_message(protocol, rsmp_version, sxl_version, site_id, message_id)
      protocol.write_lines %({"mType":"rSMsg","type":"Version","RSMP":[{"vers":"#{rsmp_version}"}],"siteId":[{"sId":"#{site_id}"}],"SXL":"#{sxl_version}","mId":"#{message_id}"})
    end

    def send_watchdog_message(protocol, timestamp, message_id)
      protocol.write_lines %({"mType":"rSMsg","type":"Watchdog","wTs":"#{timestamp}","mId":"#{message_id}"})
    end

    def expect_watchdog_message(message, expected_m_id)
      expect(message['mType']).to be == 'rSMsg'
      expect(message['type']).to be == 'Watchdog'
      expect(message['mId']).to be == expected_m_id
    end

    def parse_message(protocol)
      JSON.parse protocol.read_line
    end

    def supervisor_accept_logic(protocol)
      handle_supervisor_version_exchange(protocol)
      handle_supervisor_watchdog_exchange(protocol)
    end

    def handle_supervisor_version_exchange(protocol)
      message = parse_message(protocol)
      expect(message['mType']).to be == 'rSMsg'
      expect(message['type']).to be == 'Version'
      expect(message['siteId']).to be == [{ 'sId' => test_data[:site_id] }]
      expect(message['RSMP']).to be == test_data[:core_versions_array]
      expect(message['SXL']).to be == test_data[:sxl_version]

      send_message_ack(protocol, message['mId'])

      send_version_message(protocol, test_data[:core_versions].last, test_data[:sxl_version], test_data[:site_id], test_data[:message_ids][:version_from_supervisor])

      message = parse_message(protocol)
      expect(message['mType']).to be == 'rSMsg'
      expect(message['type']).to be == 'MessageAck'
      expect(message['oMId']).to be == test_data[:message_ids][:version_from_supervisor]
      expect(message['mId']).to be_nil
    end

    def handle_supervisor_watchdog_exchange(protocol)
      message = parse_message(protocol)
      expect_watchdog_message(message, test_data[:message_ids][:watchdog_from_site])

      send_message_ack(protocol, message['mId'])

      send_watchdog_message(protocol, test_data[:watchdog_timestamp], test_data[:message_ids][:watchdog_from_supervisor])

      watchdog_ack = parse_message(protocol)
      expect(watchdog_ack['mType']).to be == 'rSMsg'
      expect(watchdog_ack['type']).to be == 'MessageAck'
      expect(watchdog_ack['oMId']).to be == test_data[:message_ids][:watchdog_from_supervisor]
    end

    def site_interaction_logic(site_protocol)
      handle_site_version_exchange(site_protocol)
      handle_site_watchdog_exchange(site_protocol)
    end

    def handle_site_version_exchange(site_protocol)
      site_protocol.write_lines %({"mType":"rSMsg","type":"Version","RSMP":#{test_data[:core_versions_array].to_json},"siteId":[{"sId":"#{test_data[:site_id]}"}],"SXL":"#{test_data[:sxl_version]}","mId":"#{test_data[:message_ids][:version_from_site]}"})

      message = parse_message(site_protocol)
      expect(message['mType']).to be == 'rSMsg'
      expect(message['type']).to be == 'MessageAck'
      expect(message['oMId']).to be == test_data[:message_ids][:version_from_site]

      message = parse_message(site_protocol)
      expect(message['mType']).to be == 'rSMsg'
      expect(message['type']).to be == 'Version'
      expect(message['RSMP']).to be == [{ 'vers' => test_data[:core_versions].last }]
      expect(message['SXL']).to be == test_data[:sxl_version]
      expect(message['mId']).to be == test_data[:message_ids][:version_from_supervisor]

      send_message_ack(site_protocol, message['mId'])
    end

    def handle_site_watchdog_exchange(site_protocol)
      send_watchdog_message(site_protocol, test_data[:watchdog_timestamp], test_data[:message_ids][:watchdog_from_site])

      message = parse_message(site_protocol)
      expect(message['mType']).to be == 'rSMsg'
      expect(message['type']).to be == 'MessageAck'
      expect(message['oMId']).to be == test_data[:message_ids][:watchdog_from_site]

      message = parse_message(site_protocol)
      expect_watchdog_message(message, test_data[:message_ids][:watchdog_from_supervisor])

      send_message_ack(site_protocol, message['mId'])
    end

    it 'exchanges messages manually without Site or Supervisor objects' do
      uuids = [
        test_data[:message_ids][:version_from_site],
        test_data[:message_ids][:watchdog_from_site],
        '1e363b78-a67a-40f0-a2b1-acb231656594',
        test_data[:message_ids][:version_from_supervisor],
        'd5ccbf4b-e951-4476-bf23-8aa8f6835fb5',
        '3942bc2b-c0dc-45be-b3bf-b25e3afa300f',
        '0459805f-73aa-41b1-beed-11852f62756d',
        '16ec49e4-6ac1-4da6-827c-2a6562b91731'
      ].each
      mock(SecureRandom).replace(:uuid) { uuids.next }

      ready = Async::Condition.new
      accept_task = nil

      with_async_context(context: lambda {
        endpoint = IO::Endpoint.tcp('localhost', 13_112)

        accept_task = Async::Task.current.async do |task|
          task.annotate 'test supervisor accept loop'

          endpoint.accept do |socket, _address|
            stream = IO::Stream::Buffered.new(socket)
            protocol = RSMP::Protocol.new(stream)
            supervisor_accept_logic(protocol)
          end

          ready.signal
        rescue Async::Stop
          break
        end
      }) do
        site_endpoint = IO::Endpoint.tcp('localhost', 13_112)

        ready.wait

        site_socket = site_endpoint.connect
        site_stream = IO::Stream::Buffered.new(site_socket)
        site_protocol = RSMP::Protocol.new(site_stream)

        site_interaction_logic(site_protocol)

        site_socket.close
      rescue StandardError
      ensure
        expect(accept_task).not.to be_nil
        accept_task&.stop
      end
    end
  end
end
