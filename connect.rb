require 'async'
require 'async/io'

# client
client_thread = Thread.new do
  5.times do
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
  timeout = 20
  delay = 5
  puts "server: initial delay of #{delay}s"
  sleep delay

  server = TCPServer.new 12111
  puts 'server: waiting for client to connect'
  client = server.accept 
  puts "server: client connected - success"
  exit
end

client_thread.join
server_thread.join
