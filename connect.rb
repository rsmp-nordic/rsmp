require 'async'
require 'async/io'

# client
client_thread = Thread.new do
  loop do
    puts "client: trying to connect to server"
    socket = TCPSocket.new 'localhost', 12111
    puts "client: connected to server"
    break
  rescue StandardError => e
    puts "client: error while connecting: #{e.inspect}"
    sleep 1
  end
end

server_thread = Thread.new do
  delay = 4
  puts "server: initial delay of #{delay}s"
  sleep delay

  server = TCPServer.new 12111
  puts 'server: waiting for client to connect'
  client = server.accept 
  puts "server: client connected - success"
  exit
end

timeout_thread = Thread.new do
  timeout = 10
  sleep timeout
  puts "timout: client didn't connect within #{timeout}s - failure"
  exit 1
end

#client_thread.join
#server_thread.join
timeout_thread.join