require_relative '../../server'
require 'rspec/expectations'

After do |scenario|
	if $server
		$server.stop
	end
end
