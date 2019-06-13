require_relative '../../server'
require 'rspec/expectations'
require_relative 'launcher'

Before do |scenario|
	unless scenario.source_tag_names.include? "@manual_connection"
		$env.start
		@server = $env.server
		@client = $env.client
	end
	@sites_settings = $env.sites_settings
	@main_site_settings = @sites_settings.first
	@supervisor_settings = $env.supervisor_settings
end

Before('@manual_connection') do
	$env.stop
end

$env = Launcher.new
at_exit do
	$env.stop
end
