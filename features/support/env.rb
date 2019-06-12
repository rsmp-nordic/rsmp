require_relative '../../server'
require 'rspec/expectations'
require_relative 'launcher'

Before do |scenario|
	unless scenario.source_tag_names.include? "@manual_connection"
		$env.start_server
		@server = $env.server
		@client = $env.client
	end
	@site_settings = $env.site_settings
	@supervisor_settings = $env.supervisor_settings
end

Before('@manual_connection') do
	$env.stop_server
end

$env = Launcher.new
at_exit do
	$env.stop_server
end
