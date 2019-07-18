require 'async/io'

def echo_server(endpoint)
	Async do |task|
		# This is a synchronous block within the current task:
		endpoint.accept do |client|
			# This is an asynchronous block within the current reactor:
			data = client.read
			
			# This produces out-of-order responses.
			task.sleep(rand * 0.01)
			
			client.write(data.reverse)
			client.close_write
		end
	end
end

def echo_client(endpoint, data)
	Async do |task|
		endpoint.connect do |peer|
			peer.write(data)
			peer.close_write
			
			message = peer.read
			
			puts "Sent #{data}, got response: #{message}"
		end
	end
end

Async do
	endpoint = Async::IO::Endpoint.tcp('0.0.0.0', 9000)
	
	server = echo_server(endpoint)
	
	5.times.collect do |i|
		echo_client(endpoint, "Hello World #{i}")
	end.each(&:wait)
	
	server.stop
end