# test sending commands between supervisor and site
# supervisor and site can either both be either internal, or one of them can be external,
# in case you're testing equipment or other software systems

require_relative 'helpers/launcher'
require_relative '../supervisor'
require_relative '../site'


def up &block
	Async do |task|
		@supervisor.start
		@site.start

		@supervisor_connector = @supervisor.wait_for_site "RN+SI0001", 10
		@supervisor_connector.wait_for_state :ready, 0.1
		
		yield task
		
		@site.stop
		@supervisor.stop
	end
end

describe RSMP::Supervisor do

	before(:all) do
		supervisor_settings = {
			'log' => {
				'active' => true,
				'color' => :light_blue,
				'ip' => false,
				'timestamp' => false,
				'site_id' => false,
				'level' => false,
				'acknowledgements' => false,
				'watchdogs' => false
			}
		}


		@supervisor = RSMP::Supervisor.new(supervisor_settings:supervisor_settings)
		
		site_settings = {
			'log' => {
				'active' => true,
				'color' => :light_black,
				'ip' => false,
				'timestamp' => false,
				'site_id' => false,
				'level' => false,
				'acknowledgements' => false,
				'watchdogs' => false
			}
		}

		@site = RSMP::Site.new(
      site_settings: site_settings,
    )
	end

	after (:all) do
	end

	context 'sending command'
		it 'sends valid arguments' do
			up do |task|
				supervisor_start_index = @supervisor.archive.current_index
				task.async do
					@supervisor_connector.send_command 'AA+BBCCC=DDDEE001', [{"cCI":"MA104","n":"message","cO":"","v":"Rainbows!"}]
				end

				expect(@supervisor_connector.wait_for_command_response component: 'AA+BBCCC=DDDEE001', timeout: 0.1).to be_a(RSMP::CommandResponse)
				end
			#p supervisor_start_index
			#@supervisor.archive.items[supervisor_start_index..-1].each do |item|
			#	p [item[:index],item[:str]]
			#end
		end

		#it 'sends invalid arguments' do
		#	@supervisor_connector.send_command 'AA+BBCCC=DDDEE001', [{"cCI":"MA104","cO":"","v":"Rainbows!"}]
		#	expect( @supervisor_connector.wait_for_command_response component: 'AA+BBCCC=DDDEE001', timeout: 0.1).to be_nil
		#end
	end
