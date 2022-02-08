require 'async'
require 'async/io'

# client
client_thread = Thread.new do
  Async do |task|
    timeout = 10

    task.async do |connect_task|
      endpoint = Async::IO::Endpoint.tcp('127.0.0.1', 13111)
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
  Async do |task|
    timeout = 10

    endpoint = Async::IO::Endpoint.tcp('0.0.0.0', 13111)
    puts 'server: waiting for client to connect'
    tasks = endpoint.accept do |socket|  # creates async tasks
      puts "server: client connected - success"
      exit
    end

#    task.async do |cancel_task|
#      cancel_task.sleep timeout
#      puts "client did not connect within #{timeout} sec"
#      exit 1
#    end
  end
end


client_thread.join
server_thread.join
