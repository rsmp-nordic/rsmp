require 'socket'

# client
client_thread = Thread.new do
  5.times do
    puts "client: connecting"
    socket = TCPSocket.new 'localhost', 13111
    puts "client: connected"
    break
  rescue StandardError => e
    puts "couldn't not connect: #{e.inspect}"
    sleep 1
  end
end

# server
server_thread = Thread.new do
  puts "server: delay before starting"
  sleep 3
  server = TCPServer.new 13111
  puts "server: waiting for client"
  client = server.accept 
  puts "server: client connected"
end

server_thread.join
client_thread.join

puts "done"