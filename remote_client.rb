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

      # FIXME should not start until version is aknowledged
      @watchdog = start_watchdog

      # wait for all thread to complete
      @reader.join
      @watchdog.kill
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
              puts "err: #{e}"
              puts e.backtrace
            end
          end
        end
      end
    end

    def start_watchdog
      Thread.new(@client) do |socket|
        loop do
          message = Watchdog.new( {"wTs" => Server.now_utc})
          send message
          sleep 60 #TODO read from settings
        end
      end
    end

    def send message
      message.generate_json
      puts "#{Server.now_utc} #{@info[:id].to_s.rjust(3)} <-- #{message.attributes["type"]}"
      @client.puts message.out
    end

    def process packet
      message = Message.parse packet
      unless message.is_a? RSMP::Unknown
        puts "#{Server.now_utc} #{@info[:id].to_s.rjust(3)} --> #{message.attributes["type"]}"
        acknowledged message
      else
        reason = "Unknown type: #{message.attributes["type"]}"
        puts "#{Server.now_utc} #{@info[:id].to_s.rjust(3)} --> #{reason}"
        not_acknowledged message, reason
      end
    rescue
        puts "#{Server.now_utc} #{@info[:id].to_s.rjust(3)} --> Invalid package"        
    end

    def acknowledged message
      message = Acknowledged.new({
        "oMId" => message.attributes["mId"]
      })
      send message
    end

    def not_acknowledged message, reason=nil
      message = NotAcknowledged.new({
        "oMId" => message.attributes["mId"],
        "rea" => reason || "Unknown reason"
      })
      send message
    end

  end

end