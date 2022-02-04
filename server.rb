require 'async'
require 'async/io'

Async do
	endpoint = Async::IO::Endpoint.tcp('0.0.0.0', 13111)
	tasks = endpoint.accept do |socket|  # creates async tasks
	  puts "client connected"
	  exit
	end
	puts "waiting for client"
	tasks.each { |task| task.wait }
end
