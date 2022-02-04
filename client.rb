require 'async'
require 'async/io'

Async do |task|
	timeout = 10

	task.async do |connect_task|
	  endpoint = Async::IO::Endpoint.tcp('127.0.0.1', 13111)
		loop do
		  puts "connecting to server"
			endpoint.connect
			puts 'connected'
			exit
		rescue StandardError => e
			puts "error while connecting: #{e.inspect}"
			connect_task.sleep 1
		end
	end

	task.async do |cancel_task|
		cancel_task.sleep timeout
		puts "could not connect within #{timeout} sec"
		exit 1
	end
end
