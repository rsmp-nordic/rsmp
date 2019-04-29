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
        # rsmp messages are json terminated with a form-feed,
        # so read until we get a form-feed
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
      name = "watchdog"
      interval = @server.settings["watchdog_interval"]
      puts "#{prefix} Starting #{name} with interval of #{interval} seconds"
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            message = Watchdog.new( {"wTs" => Server.now_string})
            send message
          rescue StandardError => e
            puts "#{prefix} #{name} error: #{e}"
            puts e.backtrace
          ensure
            sleep interval
          end
        end
      end
    end

    def start_timeout
      name = "timeout checker"
      interval = 1
      puts "#{prefix} Starting #{name} with interval #{interval}"
      @latest_watchdog_received = Server.now_object
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            now = Server.now_object
            break if check_ack_timeout now
            break if check_watchdog_timeout now
          rescue StandardError => e
            puts "#{prefix} #{name}: #{e}"
            puts e.backtrace
          ensure
            sleep 1
          end
        end
      end
    end

    def check_ack_timeout now
      timeout = @server.settings["acknowledgement_timeout"]
      @awaiting_acknowledgement.each_pair do |mId, data|
        latest = data["timestamp"] + timeout
        if now > latest
          puts "#{prefix} Did not receive acknowledgements for #{data["type"]} messsage #{mId} within #{timeout} seconds, closing connection"
          terminate
          true
        end
      end
      false
    end

    def check_watchdog_timeout now
      timeout = @server.settings["watchdog_timeout"]
      latest = @latest_watchdog_received + timeout
      if now > latest
        puts "#{prefix} Did not receive Watchdog within #{timeout} seconds, closing connection"
        terminate
        true
      end
      false
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

      # check_site_id
      rsmp_version = check_rsmp_version message
      #check_sxl_version

      version_accepted message, rsmp_version
    end

    def check_rsmp_version message
      # find versions that both we and the client support
      candidates = message.versions & @server.rsmp_versions
      if candidates.any?
        # pick latest version
        version = candidates.sort.last
        puts "#{prefix} Received Version, using #{version}: #{message.attributes.inspect}"
        return version
      else
        reason = "RSMP versions [#{message.versions.join(',')}] were requested, but we only support [#{@server.rsmp_versions.join(',')}]."
        not_acknowledged message, reason
        terminate
        return nil
      end
    end

    def version_accepted message, rsmp_version
      start_timeout
      acknowledged message
      send_version rsmp_version
      start_watchdog
      @version_determined = true
    end

    def send_version rsmp_version
      version_response = Version.new({
        "RSMP"=>[{"vers"=>rsmp_version}],
        "siteId"=>[{"sId"=>@server.site_id}],
        "SXL"=>"1.9"
      })
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