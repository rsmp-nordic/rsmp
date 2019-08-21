require_relative '../../supervisor'
require_relative '../../site'
require_relative '../helpers/supervisor_runner'


describe RSMP::Supervisor do	
	context 'when connecting' do
		#it 'site send correct connection sequence' do
		#	connected do |task|
		#		puts "Waiting for site to connect..."
		#		remote_site = supervisor.wait_for_site(:any,10)
		#		if remote_site
		#			puts "Site connected"
		#		else
		#			raise "Site connect timeout"
		#		end
#
	  #  	# TODO the sequence differs a bit between RSMP versions
	  #  	sequence = [
		#      ['in','Version'],
		#      ['out','MessageAck'],
		#      ['out','Version'],
		#      ['in','MessageAck'],
		#      ['in','Watchdog'],
		#      ['out','MessageAck'],
		#      ['out','Watchdog'],
		#      ['in','MessageAck'],
		#      ['in','AggregatedStatus'],
		#      ['out','MessageAck'],
		#    ]
#
		#	  items = supervisor.archive.capture task, with_message: true, num: sequence.size, timeout: 10, from: 0
		#	  got = items.map { |item| item[:message] }.map { |message| [message.direction.to_s, message.type] }
		#	  expect(got).to eq(sequence)
#
		#	  expect(remote_site.ready?).to be true
#
		#	  supervisor.stop
		#	end
		#end

		it 'responds to command request' do
			SupervisorRunner.instance.connected do |task,site|
	    	site.send_command 'AA+BBCCC=DDDEE001', [{"cCI":"MA104","n":"message","cO":"","v":"Rainbows!"}]
				expect(site.wait_for_command_response component: 'AA+BBCCC=DDDEE001', timeout: 0.1).to be_a(RSMP::CommandResponse)
			end
		end

		it 'responds to command request' do
			SupervisorRunner.instance.connected do |task,site|
	    	site.send_command 'AA+BBCCC=DDDEE001', [{"cCI":"MA104","n":"message","cO":"","v":"Rainbows!"}]
				expect(site.wait_for_command_response component: 'AA+BBCCC=DDDEE001', timeout: 0.1).to be_a(RSMP::CommandResponse)
			end
		end
	end
end
