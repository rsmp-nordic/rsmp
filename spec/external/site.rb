require_relative '../../supervisor'
require_relative '../../site'
require_relative '../../supervisor_connector'

describe RSMP::Supervisor do
	
	context 'when connecting' do
		it 'site send correct connection sequence' do
			supervisor = RSMP::Supervisor.new supervisor_settings: { 'log' => { 'active' => false }}
			Async do |task|
				task.async do
					supervisor.start
				end

				puts "Waiting for site to connect..."
				remote_site = supervisor.wait_for_site(:any,10)
				puts "Site connected"
	    	
	    	# TODO the sequence differs a bit between RSMP versions
	    	sequence = [
		      ['in','Version'],
		      ['out','MessageAck'],
		      ['out','Version'],
		      ['in','MessageAck'],
		      ['in','Watchdog'],
		      ['out','MessageAck'],
		      ['out','Watchdog'],
		      ['in','MessageAck'],
		      ['in','AggregatedStatus'],
		      ['out','MessageAck'],
		    ]

			  items = supervisor.archive.capture task, with_message: true, num: sequence.size, timeout: 1, from: 0
			  got = items.map { |item| item[:message] }.map { |message| [message.direction.to_s, message.type] }
			  expect(got).to eq(sequence)

			  expect(remote_site.ready?).to be true

			  supervisor.stop
			end
		end

		it 'site sends watchdog messages' do
			supervisor = RSMP::Supervisor.new supervisor_settings: { 'log' => { 'active' => false }}
			Async do |task|
				task.async do
					supervisor.start
				end

				puts "Waiting for site to connect..."
				remote_site = supervisor.wait_for_site(:any,10)
				remote_site.wait_for_state(:ready,10)
				puts "Site connected and ready"
	    	

	    	# test other stuff...
	    	
			  supervisor.stop
			end
		end
	end
end
