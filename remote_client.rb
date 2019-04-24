# handles connection to a single remote client

require 'date'
require_relative 'message'
require_relative 'error'

module RSMP  
  class RemoteClient

    attr_reader :site_id

    def initialize client, info
      @client = client
      @info = info
      @threads = []
    end

    def run
      @reader = start_reading

      # wait for all thread to complete
      @reader.join
      @watchdog.kill if @watchdog
    end

    def start_reading      
      Thread.new(@client) do |socket|
        # rsmp messages are json terminatd with a form-feed. so red. until a form-feed
        while packet = socket.gets(Server::WRAPPING_DELIMITER)
          if packet
            packet.chomp!(Server::WRAPPING_DELIMITER)
            begin
              process packet
            rescue StandardError => e
              puts "#{Server.now_utc} #{@info[:id].to_s.rjust(3)} Error: #{e}"
              puts e.backtrace
            end
          end
        end
      end
    end

    def start_watchdog
      puts "#{prefix} Starting watchdog"
      @watchdog = Thread.new(@client) do |socket|
        loop do
          sleep 60 #TODO read from settings
          message = Watchdog.new( {"wTs" => Server.now_utc})
          send message
        end
      end
    end

    def send message
      message.generate_json
      puts "#{prefix} Sent #{message.attributes["type"]}: #{message.attributes.inspect}"
      @client.puts message.out
    end

    def process_version message
      puts "#{prefix} Received #{message.attributes["type"]}: #{message.attributes.inspect}"
      acknowledged message
      start_watchdog
    end

    def process packet
      message = Message.parse packet
      case message
        when Version
          process_version message
        when Watchdog, AggregatedStatus, Alarm
          puts "#{prefix} Received #{message.attributes["type"]}: #{message.attributes.inspect}"
          acknowledged message
        else
          puts "#{prefix} Received unknown (#{message.attributes["type"]}): #{message.attributes.inspect}"
          not_acknowledged message, "Unknown message"
      end
    rescue InvalidPacket => e
      puts "#{prefix} Received invalid package, size=#{packet.size}, content=#{e.message}"
    rescue InvalidJSON => e
      puts "#{prefix} Received invalid JSON"
    rescue InvalidMessage => e
      puts "#{prefix} Received invalid message"
    end

    def acknowledged message
      message = Acknowledged.build_from(message)
      send message
    end

    def not_acknowledged message, reason=nil
      message = NotAcknowledged.new({
        "oMId" => message.attributes["mId"],
        "rea" => reason || "Unknown reason"
      })
      send message
    end

    def prefix
      "#{Server.now_utc} #{@info[:id].to_s.rjust(3)}"
    end

  end

end