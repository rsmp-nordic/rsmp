# test sending commands between supervisor and site
# supervisor and site can either both be either internal, or one of them can be external,
# in case you're testing equipment or other software systems

require_relative 'helpers/launcher'
require_relative '../supervisor'
require_relative '../site'

describe RSMP::Supervisor do

	before(:all) do
		supervisor_settings = {
			'site_id' => 'RN+SU0001',
			'port' => 12111,
			'rsmp_versions' => ['3.1.4'],
			'timer_interval' => 0.1,
			'watchdog_interval' => 1,
			'watchdog_timeout' => 2,
			'acknowledgement_timeout' => 2,
			'command_response_timeout' => 1,
			'status_response_timeout' => 1,
			'status_update_timeout' => 1,
			'site_connect_timeout' => 2,
			'site_ready_timeout' => 1,
			'log' => {
				'active' => true,
				'color' => :light_blue,
				'ip' => false,
				'timestamp' => false,
				'site_id' => false,
				'level' => false
			}
		}

		sites_settings = [
			{ 'site_id' => 'RN+SI0001', sxl_versions: ['1,1']}
		]

		@supervisor = RSMP::Supervisor.new(supervisor_settings:supervisor_settings,sites_settings:sites_settings)
		@supervisor.start
		site_settings = {
			'site_id' => 'RN+SI0001',
			'supervisors' => [
				{ 'ip' => '127.0.0.1', 'port' => 12111 }
			],
			'rsmp_versions' => ['3.1.4'],
			'timer_interval' => 0.1,
			'watchdog_interval' => 1,
			'watchdog_timeout' => 2,
			'acknowledgement_timeout' => 2,
			'command_response_timeout' => 1,
			'status_response_timeout' => 1,
			'status_update_timeout' => 1,
			'site_connect_timeout' => 2,
			'site_ready_timeout' => 1,
			'log' => {
				'active' => true,					# set to true to debug
				'color' => :light_black,
				'ip' => false,
				'timestamp' => false,
				'site_id' => false,
				'level' => false
			}
		}

		@site = RSMP::Site.new(
      site_settings: site_settings,
    )
    @site.start

		@supervisor_connector = @supervisor.wait_for_site "RN+SI0001", 0.1
		@supervisor_connector.wait_for_state :ready, 0.1
	end

	after (:all) do
		@site.stop
		@supervisor.stop
	end

	context 'sending command'
		it 'sends valid arguments' do
			supervisor_start_index = @supervisor.archive.current_index
			@supervisor_connector.send_command 'AA+BBCCC=DDDEE001', [{"cCI":"MA104","n":"message","cO":"","v":"Rainbows!"}]
			expect( @supervisor_connector.wait_for_command_response component: 'AA+BBCCC=DDDEE001', timeout: 0.1).to be_a(RSMP::CommandResponse)
			
			#p supervisor_start_index
			#@supervisor.archive.items[supervisor_start_index..-1].each do |item|
			#	p [item[:index],item[:str]]
			#end
		end

		it 'sends invalid arguments' do
			@supervisor_connector.send_command 'AA+BBCCC=DDDEE001', [{"cCI":"MA104","cO":"","v":"Rainbows!"}]
			expect( @supervisor_connector.wait_for_command_response component: 'AA+BBCCC=DDDEE001', timeout: 0.1).to be_nil
		end
	end
