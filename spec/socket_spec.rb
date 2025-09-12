RSpec.describe RSMP::Supervisor do
  let(:timeout) { 0.01 }

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

  describe 'connection handshake' do
    let(:endpoint) {
      IO::Endpoint.tcp("127.0.0.1", supervisor.supervisor_settings['port'])
    }

    let(:socket) {
      endpoint.connect
    }

    let(:stream) {
      IO::Stream::Buffered.new(socket)
    }

    let(:protocol) {
      RSMP::Protocol.new(stream) # rsmp messages are json terminated with a form-feed
    }

    let(:ready) {
      Async::Condition.new
    }

    it 'exchanges messages manually without Site or Supervisor objects' do
      #puts "[DEBUG] #{Time.now} - Starting test"
      
      # mock SecureRandom.uuid() so we get known message ids:
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

      accept_task = nil
      
      AsyncRSpec.async context: lambda {
        #puts "[DEBUG] #{Time.now} - Setting up supervisor endpoint"
        # Acts as a supervisor by listening for connections
        endpoint = IO::Endpoint.tcp('localhost', 13112)  # use different port to avoid conflicts
        #puts "[DEBUG] #{Time.now} - Created supervisor endpoint"
        

        accept_task = Async::Task.current.async do |task|
          task.annotate "test supervisor accept loop"
          #puts "[DEBUG] #{Time.now} - Starting accept loop"
          
          endpoint.accept do |socket, address|
            #puts "[DEBUG] #{Time.now} - Accepted connection from #{address}"
            stream = IO::Stream::Buffered.new(socket)
            protocol = RSMP::Protocol.new(stream)

            # read version from site
            #puts "[DEBUG] #{Time.now} - Reading version message from site"
            message = JSON.parse protocol.read_line
            #puts "[DEBUG] #{Time.now} - Received version message: #{message['type']}"
            
            core_versions = RSMP::Schema.core_versions
            core_versions_array = core_versions.map { |version| { "vers" => version } }
            sxl_version = RSMP::Schema.latest_version(:tlc)

            expect(message['mType']).to eq('rSMsg')
            expect(message['type']).to eq('Version')
            expect(message['siteId']).to eq([{"sId"=>"RN+SI0001"}])
            expect(message['RSMP']).to eq(core_versions_array)
            expect(message['SXL']).to eq(sxl_version)
            #puts "[DEBUG] #{Time.now} - Version message validated"

            # send version ack
            #puts "[DEBUG] #{Time.now} - Sending version ack"
            protocol.write_lines JSON.generate("mType"=>"rSMsg","type"=>"MessageAck","oMId"=>message["mId"])
            #puts "[DEBUG] #{Time.now} - Version ack sent"

            # write version message from supervisor
            #puts "[DEBUG] #{Time.now} - Sending version message from supervisor"
            protocol.write_lines %/{"mType":"rSMsg","type":"Version","RSMP":[{"vers":"#{core_versions.last}"}],"siteId":[{"sId":"RN+SI0001"}],"SXL":"#{sxl_version}","mId":"51931724-b143-45a3-aa43-171f79ebb337"}/
            #puts "[DEBUG] #{Time.now} - Version message sent from supervisor"

            # read version ack from site
            #puts "[DEBUG] #{Time.now} - Reading version ack from site"
            message = JSON.parse protocol.read_line
            #puts "[DEBUG] #{Time.now} - Received version ack"
            expect(message['mType']).to eq('rSMsg')
            expect(message['type']).to eq('MessageAck')
            expect(message['oMId']).to eq('51931724-b143-45a3-aa43-171f79ebb337')
            expect(message['mId']).to be_nil

            # read watchdog from site
            #puts "[DEBUG] #{Time.now} - Reading watchdog from site"
            message = JSON.parse protocol.read_line
            #puts "[DEBUG] #{Time.now} - Received watchdog from site"
            expect(message['mType']).to eq('rSMsg')
            expect(message['type']).to eq('Watchdog')

            # send watchdog ack
            #puts "[DEBUG] #{Time.now} - Sending watchdog ack"
            protocol.write_lines %/{"mType":"rSMsg","type":"MessageAck","oMId":"#{message["mId"]}"}/
            #puts "[DEBUG] #{Time.now} - Watchdog ack sent"

            # send watchdog from supervisor
            #puts "[DEBUG] #{Time.now} - Sending watchdog from supervisor"
            protocol.write_lines %/{"mType":"rSMsg","type":"Watchdog","wTs":"2022-09-08T13:10:24.695Z","mId":"439e5748-0662-4ab2-a0d7-80fc680f04f5"}/
            #puts "[DEBUG] #{Time.now} - Watchdog sent from supervisor"

            # read watchdog ack from site
            #puts "[DEBUG] #{Time.now} - Reading watchdog ack from site"
            watchdog_ack = JSON.parse protocol.read_line
            #puts "[DEBUG] #{Time.now} - Received watchdog ack from site"
            expect(watchdog_ack['mType']).to eq('rSMsg')
            expect(watchdog_ack['type']).to eq('MessageAck')
            expect(watchdog_ack['oMId']).to eq('439e5748-0662-4ab2-a0d7-80fc680f04f5')
            #puts "[DEBUG] #{Time.now} - Supervisor side completed successfully"
  
          rescue EOFError => e
            #puts "[DEBUG] #{Time.now} - EOFError in supervisor: #{e}"
            puts e.backtrace
          rescue StandardError => e
            #puts "[DEBUG] #{Time.now} - StandardError in supervisor: #{e}"
            puts e.backtrace
          end
          ##puts "[DEBUG] #{Time.now} - signaling supervisor is ready"
          ready.signal
        rescue Async::Stop   # will happen at cleanup
          #puts "[DEBUG] #{Time.now} - Accept task stopped"
        rescue StandardError => e
          #puts "[DEBUG] #{Time.now} - Accept task error: #{e}"
          puts e.backtrace
        end
        
        #puts "[DEBUG] #{Time.now} - Accept task created"
      } do
        #puts "[DEBUG] #{Time.now} - Starting site side"
        # Acts as a site by connecting to supervisor
        site_endpoint = IO::Endpoint.tcp('localhost', 13112)
        #puts "[DEBUG] #{Time.now} - Site endpoint created"

        ##puts "[DEBUG] #{Time.now} - waiting to supervisor ready condition"
        ready.wait

        #puts "[DEBUG] #{Time.now} - Connect to supervisor"
        site_socket = site_endpoint.connect
        #puts "[DEBUG] #{Time.now} - Site connected successfully"
        site_stream = IO::Stream::Buffered.new(site_socket)
        site_protocol = RSMP::Protocol.new(site_stream)

        core_versions = RSMP::Schema.core_versions
        core_versions_array = core_versions.map { |version| { "vers" => version } }
        sxl_version = RSMP::Schema.latest_version(:tlc)

        # send version from site
        #puts "[DEBUG] #{Time.now} - Sending version from site"
        site_protocol.write_lines %/{"mType":"rSMsg","type":"Version","RSMP":#{core_versions_array.to_json},"siteId":[{"sId":"RN+SI0001"}],"SXL":"#{sxl_version}","mId":"1b206e56-31be-4739-9164-3a24d47b0aa2"}/
        #puts "[DEBUG] #{Time.now} - Version sent from site"

        # read version ack from supervisor
        #puts "[DEBUG] #{Time.now} - Reading version ack from supervisor"
        message = JSON.parse site_protocol.read_line
        #puts "[DEBUG] #{Time.now} - Received version ack from supervisor"
        expect(message['mType']).to eq('rSMsg')
        expect(message['type']).to eq('MessageAck')
        expect(message['oMId']).to eq('1b206e56-31be-4739-9164-3a24d47b0aa2')

        # read version from supervisor
        #puts "[DEBUG] #{Time.now} - Reading version from supervisor"
        message = JSON.parse site_protocol.read_line
        #puts "[DEBUG] #{Time.now} - Received version from supervisor"
        expect(message['mType']).to eq('rSMsg')
        expect(message['type']).to eq('Version')
        expect(message['RSMP']).to eq([{"vers" => core_versions.last}])
        expect(message['SXL']).to eq(sxl_version)
        expect(message['mId']).to eq('51931724-b143-45a3-aa43-171f79ebb337')

        # send version ack from site
        #puts "[DEBUG] #{Time.now} - Sending version ack from site"
        site_protocol.write_lines JSON.generate("mType"=>"rSMsg","type"=>"MessageAck","oMId"=>message["mId"])
        #puts "[DEBUG] #{Time.now} - Version ack sent from site"

        # send watchdog from site
        #puts "[DEBUG] #{Time.now} - Sending watchdog from site"
        site_protocol.write_lines %/{"mType":"rSMsg","type":"Watchdog","wTs":"2022-09-08T13:10:24.695Z","mId":"fd92d6f6-f0c3-4a91-a582-6fff4e5bb63b"}/
        #puts "[DEBUG] #{Time.now} - Watchdog sent from site"

        # read watchdog ack from supervisor
        #puts "[DEBUG] #{Time.now} - Reading watchdog ack from supervisor"
        message = JSON.parse site_protocol.read_line
        #puts "[DEBUG] #{Time.now} - Received watchdog ack from supervisor"
        expect(message['mType']).to eq('rSMsg')
        expect(message['type']).to eq('MessageAck')
        expect(message['oMId']).to eq('fd92d6f6-f0c3-4a91-a582-6fff4e5bb63b')

        # read watchdog from supervisor
        #puts "[DEBUG] #{Time.now} - Reading watchdog from supervisor"
        message = JSON.parse site_protocol.read_line
        #puts "[DEBUG] #{Time.now} - Received watchdog from supervisor"
        expect(message['mType']).to eq('rSMsg')
        expect(message['type']).to eq('Watchdog')
        expect(message['mId']).to eq('439e5748-0662-4ab2-a0d7-80fc680f04f5')

        # send watchdog ack from site
        #puts "[DEBUG] #{Time.now} - Sending watchdog ack from site"
        site_protocol.write_lines %/{"mType":"rSMsg","type":"MessageAck","oMId":"439e5748-0662-4ab2-a0d7-80fc680f04f5"}/
        #puts "[DEBUG] #{Time.now} - Final watchdog ack sent from site"

        #puts "[DEBUG] #{Time.now} - Closing site socket"
        site_socket.close
        #puts "[DEBUG] #{Time.now} - Site side completed successfully"
      rescue StandardError => e
        #puts "[DEBUG] #{Time.now} - Error in site side: #{e}"
        puts e.backtrace
      ensure
        # Clean up the accept task
        #puts "[DEBUG] #{Time.now} - Cleaning up accept task"
        if accept_task
          #puts "[DEBUG] #{Time.now} - Accept task status: #{accept_task.status}"
          accept_task.stop
          #puts "[DEBUG] #{Time.now} - Accept task stopped"
        end
        #puts "[DEBUG] #{Time.now} - Test cleanup completed"
      end
    end
  end
end
