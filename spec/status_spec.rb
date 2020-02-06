# test sending commands between supervisor and site
# supervisor and site can either both be either internal, or one of them can be external,
# in case you're testing equipment or other software systems


def up &block
	Async do |task|
		@supervisor.start
		@site.start

		@supervisor_proxy = @supervisor.wait_for_site "RN+SI0001", 1
		expect(@supervisor_proxy).to_not be_nil, "Test site did not connect"
		@supervisor_proxy.wait_for_state :ready, 0.1
		
		yield task
		
		@site.stop
		@supervisor.stop
	end
end

RSpec.describe "Sending commands" do

	before(:all) do
		supervisor_settings = { 'port' => 13111 }
		log_settings = {
			'active' => false,
			'color' => :light_blue,
			'ip' => false,
			'timestamp' => false,
			'site_id' => false,
			'level' => false,
			'acknowledgements' => false,
			'watchdogs' => false
		}


		@supervisor = RSMP::Supervisor.new(
			supervisor_settings:supervisor_settings,
			log_settings:log_settings
		)
		
		site_settings = {
			'supervisors' => [ {'ip' => '127.0.0.1', 'port' => 13111 } ],
      'components' => {
				'TC' => {
				    'type' => 'main',
				    'cycle_time' => 6
				}
			}
		}
		log_settings = {
			'active' => false,
			'color' => :light_black,
			'ip' => false,
			'timestamp' => false,
			'site_id' => false,
			'level' => false,
			'acknowledgements' => false,
			'watchdogs' => false,
			'json' => true
		}

		@site = RSMP::Tlc.new(
      site_settings: site_settings,
      log_settings:log_settings
    )
	end

	context 'sending command'
		it 'sends valid arguments' do
			up do |task|
				supervisor_start_index = @supervisor.archive.current_index
				task.async do
					@supervisor_proxy.send_command 'AA+BBCCC=DDDEE001', [{"cCI" => "M0001","n" => "status","cO" => "setValue","v" => "NormalControl"}]
				end
				expect(@supervisor_proxy.wait_for_command_response component: 'AA+BBCCC=DDDEE001', timeout: 0.1).to be_a(RSMP::CommandResponse)
			end
		end
	end
