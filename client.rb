require 'async'
require 'async/io'

timeout = 5
Async do |task|
	task.with_timeout timeout do
	  endpoint = Async::IO::Endpoint.tcp('127.0.0.1', 13111)
		loop do
		  puts "trying to connect to server"
			endpoint.connect
			puts 'connected'
			exit
		rescue StandardError => e
			task.sleep 1
		end
	rescue Async::TimeoutError
		puts "could not connect within #{timeout} sec"
		exit 1
	end
end
