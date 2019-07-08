require_relative '../../supervisor'
require 'rspec/expectations'
require_relative 'launcher'

Before do |scenario|
	unless scenario.source_tag_names.include? "@manual_connection"
		$env.start
		@supervisor = $env.supervisor
		@remote_site = $env.remote_site
	end
	@sites_settings = $env.sites_settings
	@main_site_settings = @sites_settings.first
	@supervisor_settings = $env.supervisor_settings
	@archive = $env.archive
end

Before('@manual_connection') do
	$env.stop
end


$env = Launcher.new
at_exit do
	$env.stop
end
