require_relative '../supervisor'
require_relative '../site'
require_relative '../supervisor_connector'

describe RSMP::Supervisor do
	context 'when creating' do

		let(:supervisor_settings) {
			{
				site_id: 'RN+RS0001',
				port: 12111,
				rsmp_versions: ['3.1.4'],
				timer_interval: 0.1,
				watchdog_interval: 1,
				watchdog_timeout: 2,
				acknowledgement_timeout: 2,
				command_response_timeout: 1,
				status_response_timeout: 1,
				status_update_timeout: 1,
				site_connect_timeout: 2,
				site_ready_timeout: 1,
				log: {
					"active" => true,					# set to true to debug
					"color" => :light_black,
					"ip" => false,
					"timestamp" => false,
					"site_id" => false,
					"level" => false
				}
			}
		}

		let(:sites_settings) {
			[ { "site_id"=> 'RN+SI0001', sxl_versions: ['1,1']} ]
		}


		it 'requires settings hash' do
			expect { RSMP::Supervisor.new({}) }.to raise_error(ArgumentError,"supervisor_settings or supervisor_settings_path must be present")
		end

		it 'accepts settings' do
			supervisor = RSMP::Supervisor.new(supervisor_settings:supervisor_settings,sites_settings:sites_settings)
		end

		it 'starts' do
			# mock SecureRandom.uui() so we get known message ids:
			allow(SecureRandom).to receive(:uuid).and_return(
				'1b206e56-31be-4739-9164-3a24d47b0aa2',
				'fd92d6f6-f0c3-4a91-a582-6fff4e5bb63b',
				'1e363b78-a67a-40f0-a2b1-acb231656594',
				'51931724-b143-45a3-aa43-171f79ebb337'
			)

			supervisor = RSMP::Supervisor.new(supervisor_settings:supervisor_settings,sites_settings:sites_settings)
			supervisor.start

			# create a simple tcp socket, and send a version message
			socket = TCPSocket.open "127.0.0.1", supervisor_settings[:port]
			socket.print '{"mType":"rSMsg","type":"Version","RSMP":[{"vers":"3.1.4"}],"siteId":[{"sId":"RN+SI0001"}],"SXL":"1.1","mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6"}'+"\f"

			# supervisor should see our tcp socket and create a connector
			supervisor_connector = supervisor.wait_for_site "RN+SI0001", 0.1
			expect(supervisor_connector).to be_an(RSMP::SupervisorConnector)
			expect(supervisor_connector.site_id).to eq("RN+SI0001")

			# read expected ack and version messages from the socket
			version_ack = JSON.parse socket.gets(RSMP::WRAPPING_DELIMITER).strip
			expect(version_ack['mType']).to eq('rSMsg')
			expect(version_ack['type']).to eq('MessageAck')
			expect(version_ack['oMId']).to eq('8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6')
			expect(version_ack['mId']).to match(/[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}/i)

			version = JSON.parse socket.gets(RSMP::WRAPPING_DELIMITER).strip
			socket.print JSON.generate("mType":"rSMsg","type":"MessageAck","oMId":version["mId"],"mId":"561c15c9-e050-4ee7-9cf4-8643c6769dcb")+"\f"
			expect( supervisor_connector.wait_for_state(:ready, 0.1) ).to eq(true)

			# verify log content
			expect( supervisor.archive.strings ).to eq([
				"Received Version message for sites [RN+SI0001] using RSMP 3.1.4",
				"Starting timer with interval 0.1 seconds",
				"Sent MessageAck for Version 8db0",
				"Sent Version",
				"Received MessageAck for Version fd92",
				"Connection to site established"
			])
		end

	end
end
