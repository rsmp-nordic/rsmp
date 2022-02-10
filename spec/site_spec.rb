RSpec.describe RSMP::Site do
	let(:timeout) { 0.01 }

	let(:ip) { 'localhost' }
	let(:port) { 13111 }
	let(:site_settings) {
		{
			'site_id' => 'RN+SI0001',
			'supervisors' => [
				{ 'ip' => ip, 'port' => port }
			]
		}
	}

	let(:log_settings) {
		{
			'active' => false
		}
	}

  describe '#initialize' do
		it 'accepts no options' do
			expect { RSMP::Site.new({}) }.not_to raise_error
		end

		it 'accepts options' do
			RSMP::Site.new(
				site_settings: site_settings,
				log_settings: log_settings
			)
		end
	end

	describe 'connection handshake' do
		it 'completes' do
			# mock SecureRandom.uui() so we get known message ids:
			allow(SecureRandom).to receive(:uuid).and_return(
				'1b206e56-31be-4739-9164-3a24d47b0aa2'
			)

			async_context do
				site = nil

				# acts as a supervisior by listening for connections
				# and exhcanging RSMP handhake
				endpoint = Async::IO::Endpoint.tcp('localhost', port)
				tasks = endpoint.accept do |socket|  # creates async tasks
			  	stream = Async::IO::Stream.new(socket)
			  	protocol = Async::IO::Protocol::Line.new(stream,RSMP::Proxy::WRAPPING_DELIMITER) # rsmp messages are json terminated with a form-feed
			  	
			  	# read version
			  	version = JSON.parse protocol.read_line
					expect(version).to eq({"RSMP"=>[{"vers"=>"3.1.1"}, {"vers"=>"3.1.2"}, {"vers"=>"3.1.3"}, {"vers"=>"3.1.4"}, {"vers"=>"3.1.5"}], "SXL"=>"1.0.15", "mId"=>"1b206e56-31be-4739-9164-3a24d47b0aa2", "mType"=>"rSMsg", "siteId"=>[{"sId"=>"RN+SI0001"}], "type"=>"Version"})

					# send ack
					protocol.write_lines JSON.generate("mType"=>"rSMsg","type"=>"MessageAck","oMId"=>version["mId"])

		      # write version message
					protocol.write_lines '{"mType":"rSMsg","type":"Version","RSMP":[{"vers":"3.1.5"}],"siteId":[{"sId":"RN+SI0001"}],"SXL":"1.0.15","mId":"51931724-b143-45a3-aa43-171f79ebb337"}'

					# read ack
					version_ack = JSON.parse protocol.read_line
					expect(version_ack['mType']).to eq('rSMsg')
					expect(version_ack['type']).to eq('MessageAck')
					expect(version_ack['oMId']).to eq('51931724-b143-45a3-aa43-171f79ebb337')
					expect(version_ack['mId']).to be_nil

					proxy = site.proxies.first
					expect(proxy).to be_an(RSMP::SupervisorProxy)
					expect(proxy.state).to be(:ready)
				end

			  site = RSMP::Site.new(
			  	site_settings: site_settings,
			  	log_settings: log_settings
			  )

			  site.start
			end
		end
	end
end
