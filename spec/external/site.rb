require_relative '../helpers/launcher'

include Launcher
Launcher::load_settings
Launcher::start_site

describe 'External RSMP site' do

	before(:all) do
	end

	after (:all) do
	end

	let(:supervisor) { start_supervisor }
	let(:archive) { start_supervisor; @archive }

	context 'when connecting' do
		it 'connects to the supervisor' do
			remote_site = supervisor.wait_for_site(:any, 10)
			expect(remote_site).to be_instance_of(RSMP::SupervisorConnector)
    	expect(remote_site.wait_for_state :ready, 10).to eq(true)

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

		  items = @archive.capture with_message: true, num: sequence.size, timeout: 10, from: 0
		  got = items.map { |item| item[:message] }.map { |message| [message.direction.to_s, message.type] }
		  expect(got).to eq(sequence)
		end
	end
end
