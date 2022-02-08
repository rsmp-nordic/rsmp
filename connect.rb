require 'async'
require 'async/io'

# client
client_thread = Thread.new do

  endpoint = Async::IO::Endpoint.tcp('0.0.0.0', 13111)

  Async do |task|
    timeout = 10

    task.async do |connect_task|
      endpoint = Async::IO::Endpoint.tcp('localhost', 12111)
      loop do
        puts "client: trying to connect to server"
        endpoint.connect
        puts 'client: connected to server'
        exit
      rescue StandardError => e
        puts "client: error while connecting: #{e.inspect}"
        connect_task.sleep 1
      end
    end

    task.async do |cancel_task|
      cancel_task.sleep timeout
      puts "client: could not connect within #{timeout} sec - failure"
      exit 1
    end
  end
end


server_thread = Thread.new do
  timeout = 10
  delay = 3
  puts "server: initial delay of #{delay}s"
  sleep delay

  server = TCPServer.new 13111
  puts 'server: waiting for client to connect'
  client = server.accept 
  puts "server: client connected - success"
  exit
end

client_thread.join
server_thread.join
