require_relative '../../supervisor'
require_relative '../../site'
require_relative '../helpers/supervisor_runner'
require "rspec/with_params/dsl"


describe RSMP::Supervisor do	
extend RSpec::WithParams::DSL

	context 'when connecting' do
		with_params(
			[:version,:expected_sequence],
			["3.1.1", [
				['in','Version'],
				['out','MessageAck'],
				['out','Version'],
				['in','MessageAck'],
				['in','Watchdog'],
				['out','MessageAck'],
				['out','Watchdog'],
				['in','MessageAck']
			]],
			["3.1.2", [
				['in','Version'],
				['out','MessageAck'],
				['out','Version'],
				['in','MessageAck'],
				['in','Watchdog'],
				['out','MessageAck'],
				['out','Watchdog'],
				['in','MessageAck']
			]],
			["3.1.3", [
				['in','Version'],
				['out','MessageAck'],
				['out','Version'],
				['in','MessageAck'],
				['in','Watchdog'],
				['out','MessageAck'],
				['out','Watchdog'],
				['in','MessageAck'],
				['in','AggregatedStatus'],
				['out','MessageAck']
			]],
			["3.1.4", [
				['in','Version'],
				['out','MessageAck'],
				['out','Version'],
				['in','MessageAck'],
				['in','Watchdog'],
				['out','MessageAck'],
				['out','Watchdog'],
				['in','MessageAck'],
				['in','AggregatedStatus'],
				['out','MessageAck']
			]],
		) do
			it 'exchanges correct connection sequence' do
				SupervisorRunner.without_site do |task|
					supervisor = RSMP::Supervisor.new supervisor_settings: {
						'rsmp_versions' =>  [version],
						'log' => { 'active' => false }
					}
					supervisor.start
					remote_site = SupervisorRunner.instance.wait_for_site supervisor
			
					items = supervisor.archive.capture task, with_message: true, num: expected_sequence.size, timeout: 1, from: 0
					got = items.map { |item| item[:message] }.map { |message| [message.direction.to_s, message.type] }
					expect(got).to eq(expected_sequence)
					expect(remote_site.ready?).to be true
					supervisor.stop
					task.yield
				end
			end
		end

		with_params(
			[:value,:response],
			["Rainbows!","Rainbows!"],
			[198234,198234],
			[0.0523,0.0523],
			[-0.0523,0.0523],
			["æåøÆÅØ","ææåøÆÅØ"],
			["-_,.-/\"*§!{#€%&/()=?`}","-_,.-/\"*§!{#€%&/()=?`}"],
			["",""],
			[nil,nil],
		) do
			it 'responds to command request' do
				SupervisorRunner.with_site do |task,site|
					site.send_command 'AA+BBCCC=DDDEE002', [{"cCI":"MA104","n":"message","cO":"","v":"Rainbows!"}]
					response = site.wait_for_command_response component: 'AA+BBCCC=DDDEE002', timeout: 1
					expect(response).to be_a(RSMP::CommandResponse)
					expect(response.attributes["cId"]).to eq("AA+BBCCC=DDDEE002")
					expect(response.attributes["rvs"]).to eq([{"age"=>"recent", "cCI"=>"MA104", "n"=>"message", "v"=>"Rainbows!"}])
				end
			end
		end

	end
end
