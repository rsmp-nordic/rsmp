require_relative '../../supervisor'
require_relative '../../site'
require 'rspec/expectations'
require_relative 'launcher'

Before do |scenario|
	unless scenario.source_tag_names.include? "@manual_connection"
		$launcher.start
		@supervisor = $launcher.supervisor
		@remote_site = $launcher.remote_site
	end
	@sites_settings = $launcher.sites_settings
	@main_site_settings = @sites_settings.first
	@supervisor_settings = $launcher.supervisor_settings
	@archive = $launcher.archive
end

Before('@manual_connection') do
	$launcher.stop
end

$launcher = Launcher.new
at_exit do
	$launcher.stop
end
