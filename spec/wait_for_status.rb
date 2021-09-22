RSpec.describe RSMP::Supervisor do
	context 'when creating' do

		let(:supervisor_settings) {
			{
				'port' => 13111,		# use special port to avoid sites connection during test
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
				'json' => true
			}
		}

		it 'runs without options' do
			expect { RSMP::Supervisor.new({}) }.not_to raise_error
		end

		it 'accepts options' do
			supervisor = RSMP::Supervisor.new(
				supervisor_settings: supervisor_settings,
				log_settings: log_settings
			)
		end

		it 'starts' do
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

			supervisor = RSMP::Supervisor.new(
				supervisor_settings: supervisor_settings,
				log_settings: log_settings
			)
			Async do |task|
				task.async do
					supervisor.start
				end

				# create stream
	      endpoint = Async::IO::Endpoint.tcp("127.0.0.1", supervisor.supervisor_settings['port'])
	      socket = endpoint.connect
	      stream = Async::IO::Stream.new(socket)
	      protocol = Async::IO::Protocol::Line.new(stream,RSMP::Proxy::WRAPPING_DELIMITER) # rsmp messages are json terminated with a form-feed

	      # write version message
				protocol.write_lines '{"mType":"rSMsg","type":"Version","RSMP":[{"vers":"3.1.5"}],"siteId":[{"sId":"RN+SI0001"}],"SXL":"1.0.15","mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6"}'

				# read ack
				version_ack = JSON.parse protocol.read_line
				expect(version_ack['mType']).to eq('rSMsg')
				expect(version_ack['type']).to eq('MessageAck')
				expect(version_ack['oMId']).to eq('8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6')
				expect(version_ack['mId']).to be_nil

				# read version
				version = JSON.parse protocol.read_line
				expect(version).to eq({"RSMP"=>[{"vers"=>"3.1.1"}, {"vers"=>"3.1.2"}, {"vers"=>"3.1.3"}, {"vers"=>"3.1.4"}, {"vers"=>"3.1.5"}], "SXL"=>"1.0.15", "mId"=>"1b206e56-31be-4739-9164-3a24d47b0aa2", "mType"=>"rSMsg", "siteId"=>[{"sId"=>"RN+SI0001"}], "type"=>"Version"})

				# send ack
				protocol.write_lines JSON.generate("mType"=>"rSMsg","type"=>"MessageAck","oMId"=>version["mId"],"mId"=>SecureRandom.uuid())

				# supervisor should see our tcp socket and create a proxy
				proxy = supervisor.wait_for_site "RN+SI0001", 0.1
				expect(proxy).to be_an(RSMP::SiteProxy)
				expect(proxy.site_id).to eq("RN+SI0001")



				expect {
					proxy.wait_for_state(:ready, 0.1)
				}.not_to raise_error

				# verify log content
				got = supervisor.archive.by_level([:log, :info]).map { |item| item[:str] }
				expect( got ).to match_array([
					"Starting supervisor on port 13111",
					"Site connected from ********",
					"Received Version message for site RN+SI0001",
					"Sent MessageAck for Version 8db0",
					"Sent Version",
					"Received MessageAck for Version 1b20",
					"Connection to site RN+SI0001 established, using core 3.1.5, tlc 1.0.15"
				])

				supervisor.stop
			end
		end
	end
end
