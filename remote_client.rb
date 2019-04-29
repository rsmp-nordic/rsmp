# handles connection to a single remote client

require_relative 'message'
require_relative 'error'

module RSMP  
  class RemoteClient

    attr_reader :site_id

    def initialize server, client, info
      @server = server
      @client = client
      @info = info
      @awaiting_acknowledgement = {}
      @latest_watchdog_received = nil
      @version_determined = false
      @version_message_id = nil
      @threads = []
    end

    def run
      start_reader
      @reader.join
      kill_threads
    end

    def terminate
      @reader.kill
    end

    def kill_threads
      reaper = Thread.new(@threads) do |threads|
        threads.each do |thread|
          puts "#{prefix} Stopping #{thread[:name]}"
          thread.kill
        end
      end
      reaper.join
      @threads.clear
    end

    def start_reader    
      @reader = Thread.new(@client) do |socket|
        Thread.current[:name] = "reader"
        # rsmp messages are json terminatd with a form-feed. so red. until a form-feed
        while packet = socket.gets(Server::WRAPPING_DELIMITER)
          if packet
            packet.chomp!(Server::WRAPPING_DELIMITER)
            begin
              process packet
            rescue StandardError => e
              puts "#{prefix} Read error: #{e}"
              puts e.backtrace
            end
          end
        end
      end
    end

    def start_watchdog
      interval = @server.settings["watchdog_interval"]
      name = "watchdog sender"
      puts "#{prefix} Starting #{name} with interval of #{interval} seconds"
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            message = Watchdog.new( {"wTs" => Server.now_string})
            send message
          rescue StandardError => e
            puts "#{prefix} Watchdog error: #{e}"
          ensure
            sleep interval
          end
        end
      end
    end

    def start_ack_timer
      timeout = @server.settings["acknowledgement_timeout"]
      name = "acknowledgement checker"
      puts "#{prefix} Started #{name} with timeout of #{timeout} seconds"
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          now = Server.now_object
          @awaiting_acknowledgement.each_pair do |mId, data|
            latest = data["timestamp"] + timeout
            if now > latest
              missing_acknowledgement mId, data["type"]
              break
            end
          end
          sleep 1
        end
      end
    end

    def start_watchdog_timer
      timeout = @server.settings["watchdog_timeout"]
      name = "watchdog checker"
      puts "#{prefix} Started #{name} with timeout of #{timeout} seconds"
      @latest_watchdog_received = Server.now_object
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          sleep 1
          now = Server.now_object
          latest = @latest_watchdog_received + timeout
          if now > latest
            missing_watchdog latest
            break
          end
        end
      end
    end

    def missing_watchdog latest
      puts "#{prefix} Did not receive Watchdog within #{@server.settings["watchdog_timeout"]} seconds, closing connection"
      terminate
    end

    def missing_acknowledgement mId, type
      puts "#{prefix} Did not receive acknowledgements for #{type} messsage #{mId} within #{@server.settings["acknowledgement_timeout"]} seconds, closing connection"
      terminate
    end

    def send message
      message.generate_json
      puts "#{prefix} Sent #{message.type}: #{message.attributes.inspect}"
      @client.puts message.out
      expect_acknowledgement message
      message.mId
    end

    def expect_acknowledgement message
      unless message.is_a?(MessageAck) || message.is_a?(MessageNotAck)
        @awaiting_acknowledgement[message.mId] = {
          "type" => message.type,  
          "timestamp" => Server.now_object
        }
      end
    end

    def got_acknowledgement message
      @awaiting_acknowledgement.delete message.attributes["oMId"]
    end


    def process_version message
      if @version_determined
        puts "#{prefix} Received Version message out of place"
        not_acknowledged message, "Version already received"
        return
      end

      puts "#{prefix} Received Version: #{message.attributes.inspect}"

      # check siteid

      # find versions that both we and the client support
      candidates = message.versions & @server.rsmp_versions
      if candidates.any?
        # pick latest version
        rsmp_version = candidates.sort.last
      else
        reason = "RSMP versions [#{message.versions.join(',')}] were requested, but we only support [#{@server.rsmp_versions.join(',')}]."
        not_acknowledged message, reason
      end

      # check sxl version

      # all checks succeeded
      start_ack_timer
      acknowledged message
      send_version rsmp_version

      start_watchdog_timer
      start_watchdog

      @version_determined = true
    end

    def send_version rsmp_version
      version_response = Version.new({
        "RSMP"=>[{"vers"=>rsmp_version}],
        "siteId"=>[{"sId"=>@server.site_id}],
        "SXL"=>"1.9"
      })
      @version_message_id = send version_response
      p @version_message_id
    end

    def process_ack message
      puts "#{prefix} Received #{message.type}: #{message.attributes.inspect}"
      got_acknowledgement message
    end

    def process_not_ack message
      puts "#{prefix} Received #{message.type}: #{message.attributes.inspect}"
      got_acknowledgement message
    end

    def process_watchdog message
      puts "#{prefix} Received #{message.type}: #{message.attributes.inspect}"
      @latest_watchdog_received = Server.now_object
      acknowledged message
    end

    def expect_version_message message
      unless message.is_a? Version
        puts "#{prefix} Version must be received first, but got #{message.type}, closing connection: #{message.attributes.inspect}"
        not_acknowledged message, "Version must be received first, but got #{message.type}"
        terminate
      end
    end

    def process packet
      message = Message.parse packet
      expect_version_message(message) unless @version_determined

      case message
        when MessageAck
          process_ack message
        when MessageNotAck
          process_not_ack message
        when Version
          process_version message
        when Watchdog
          process_watchdog message
        when AggregatedStatus, Alarm
          puts "#{prefix} Received #{message.type}: #{message.attributes.inspect}"
          acknowledged message
        else
          puts "#{prefix} Received unknown message (#{message.type}): #{message.attributes.inspect}"
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
      message = MessageAck.build_from(message)
      send message
    end

    def not_acknowledged message, reason=nil
      message = MessageNotAck.new({
        "oMId" => message.mId,
        "rea" => reason || "Unknown reason"
      })
      send message
    end

    def prefix
      "#{Server.now_string} #{@info[:id].to_s.rjust(3)}"
    end
  end
end