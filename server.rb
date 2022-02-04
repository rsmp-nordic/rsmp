require 'async'
require 'async/io'

Async do |task|
	timeout = 5

	endpoint = Async::IO::Endpoint.tcp('0.0.0.0', 13111)
	puts 'waiting for client to connect'
	tasks = endpoint.accept do |socket|  # creates async tasks
	  puts "client connected"
	  exit
	end

	task.async do |cancel_task|
		cancel_task.sleep timeout
		puts "client did not connect within #{timeout} sec"
		exit
	end
end
