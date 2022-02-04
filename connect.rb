require 'async'
require 'async/io'

timeout = 10
Async do |task|
  puts "try to connect to server, time out after #{timeout}s"
  task.with_timeout timeout do
    endpoint = Async::IO::Endpoint.tcp('127.0.0.1', 13111)
    endpoint.connect
  rescue StandardError => e
    puts "connect error: #{e.inspect}"
  end
rescue Async::TimeoutError
  puts "client did not connect within #{timneout}s"
end
