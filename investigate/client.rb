require 'async'
require 'async/notification'
require 'async/io/stream'
require 'async/io/host_endpoint'
require 'async/io/protocol/line'

class User < Async::IO::Protocol::Line
end

def job(name, _condition)
  Async do |t|
    t.annotate name
    loop do
      yield
    rescue StandardError => e
      Console.logger.error("#{name}: Uncaught exception #{e}")
    ensure
      sleep 1
    end
  end
end

def run(name, endpoint)
  network = nil
  terminal = nil
  user = nil
  n = 1
  socket = endpoint.connect
  Console.logger.info('connected')
  stream = Async::IO::Stream.new(socket)
  user = User.new(stream)
  finished = Async::Notification.new
  user.write_lines name

  # read from server
  network = job('network', finished) do
    while line = user.read_line
      Console.logger.info("server: #{line}")
    end
  rescue EOFError
    Console.logger.warn('disconnected')
    finished.signal
  end

  # timer
  timer = job('timer', finished) do
    loop do
      user.write_lines "ping #{n}"
      n += 1
      sleep 1
      # raise 'bah'
    end
  rescue EOFError
    Console.logger.warn('disconnected')
    finished.signal
  end

  # Wait for any of the above processes to finish:
  finished.wait
rescue Errno::ECONNREFUSED
  Console.logger.warn('no connection')
ensure
  # stop all the nested tasks if we are exiting
  network.stop if network
  network = nil
  terminal.stop if terminal
  terminal = nil
  user.close if user
  user = nil
end

begin
  Async do |task|
    task.annotate 'client'
    name = SecureRandom.uuid[0..4]
    Console.logger.info("starting #{name}")
    endpoint = Async::IO::Endpoint.parse(ARGV.pop || 'tcp://localhost:7138')
    loop do
      run name, endpoint
      sleep 1
    end
  end
rescue Interrupt
  Console.logger.info("\nBye")
end
