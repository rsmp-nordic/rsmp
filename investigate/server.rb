require 'logger'

require 'async'
require 'async/io/host_endpoint'
require 'async/io/protocol/line'

class User < Async::IO::Protocol::Line
  attr_accessor :name

  def login!
    self.name = read_line
  end

  def to_s
    @name || 'unknown'
  end
end

class Server
  def initialize
    @users = Set.new
  end

  def broadcast(*message)
    puts(*message)

    @users.each do |user|
      user.write_lines(*message)
    rescue EOFError
      # In theory, it's possible this will fail if the remote end has disconnected. Each user has it's own task running `#connected`, and eventually `user.read_line` will fail. When it does, the disconnection logic will be invoked. A better way to do this would be to have a message queue, but for the sake of keeping this example simple, this is by far the better option.
    end
  end

  def connected(user)
    user.login!
    Console.logger.info("#{user} connected")
    user.write_lines "welcome #{user}"
    while message = user.read_line
      Console.logger.info("#{user}: #{message}")
      user.write_lines 'ack'
    end
  rescue EOFError
    # It's okay, client has disconnected.
  ensure
    disconnected(user)
  end

  def disconnected(user)
    @users.delete(user)
    Console.logger.warn("#{user} disconnected")
  end

  def run(endpoint)
    Async do |_task|
      endpoint.accept do |peer|
        stream = Async::IO::Stream.new(peer)
        user = User.new(stream)
        @users << user
        connected(user)
      end
    end
  rescue Interrupt
    Console.logger.info("\nBye")
  end
end

Console.logger.level = Logger::INFO
Console.logger.info('Starting server...')
server = Server.new

endpoint = Async::IO::Endpoint.parse(ARGV.pop || 'tcp://localhost:7138')
server.run(endpoint)
