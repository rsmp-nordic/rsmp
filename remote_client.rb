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
      @threads = []
      @awaiting_acknowledgement = {}
      @ack_timer = nil
      @watchdog_timer = nil
      @latest_watchdog_received = nil
    end

    def run
      @reader = start_reading

      # wait for reader to complete, i.e. the client disconnects,
      # or the thread is killed because we disconnect
      @reader.join
      stop_watchdog
      stop_ack_timer
      stop_watchdog_timer
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
              puts "#{Server.now_string} #{@info[:id].to_s.rjust(3)} Error: #{e}"
              puts e.backtrace
            end
          end
        end
      end
    end

    def start_watchdog
      interval = @server.settings["watchdog_interval"]
      puts "#{prefix} Started watchdog with interval of #{interval} seconds"
      @watchdog = Thread.new(@client) do |socket|
        loop do
          message = Watchdog.new( {"wTs" => Server.now_string})
          send message
          sleep interval
        end
      end
    end

    def stop_watchdog
      @watchdog.kill if @watchdog
      @watchdog = nil
    end

    def start_ack_timer
      timeout = @server.settings["acknowledgement_timeout"]
      puts "#{prefix} Started acknowledgement timer with timeout of #{timeout} seconds"
      @ack_timer = Thread.new(@client) do |socket|
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

    def stop_ack_timer
      @ack_timer.kill if @ack_timer
      @ack_timer = nil
    end

    def start_watchdog_timer
      timeout = @server.settings["watchdog_timeout"]
      puts "#{prefix} Started watchdog timer with timeout of #{timeout} seconds"
      @latest_watchdog_received = Server.now_object
      @watchdog_timer = Thread.new(@client) do |socket|
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
      puts "#{prefix} Missing watchdog, latest received at #{latest}"
      terminate
    end

    def stop_watchdog_timer
      @ack_timer.kill if @ack_timer
      @ack_timer = nil
    end

    def missing_acknowledgement mId, type
      puts "#{prefix} Missing acknowledgements for #{type} messsage #{mId}, closing connection"
      terminate
    end

    def terminate
      # this might be called from one of the below threads
      # use a separate thread to ensure we're not killed halfway through
      Thread.new do
        @ack_timer.kill if @ack_timer
        @watchdog_timer.kill if @watchdog_timer
        @reader.kill if @reader
      end
    end

    def send message
      message.generate_json
      puts "#{prefix} Sent #{message.attributes["type"]}: #{message.attributes.inspect}"
      @client.puts message.out
      expect_acknowledgement message
    end

    def expect_acknowledgement message
      unless message.is_a?(MessageAck) || message.is_a?(MessageNotAck)
        @awaiting_acknowledgement[message.attributes["mId"]] = {
          "type" => message.attributes["type"],  
          "timestamp" => Server.now_object
        }
      end
    end

    def got_acknowledgement message
      @awaiting_acknowledgement.delete message.attributes["oMId"]
    end


    def process_version message
      puts "#{prefix} Received #{message.attributes["type"]}: #{message.attributes.inspect}"

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
      start_watchdog_timer
        
      # send version message, specifying the version we picked
      version_response = Version.new({
        "RSMP"=>[{"vers"=>rsmp_version}],
        "siteId"=>[{"sId"=>@server.site_id}],
        "SXL"=>"1.9"
      })
      send version_response

      start_watchdog
    end

    def process_ack message
      puts "#{prefix} Received #{message.attributes["type"]}: #{message.attributes.inspect}"
      got_acknowledgement message
    end

    def process_not_ack message
      puts "#{prefix} Received #{message.attributes["type"]}: #{message.attributes.inspect}"
      got_acknowledgement message
    end

    def process_watchdog message
      puts "#{prefix} Received #{message.attributes["type"]}: #{message.attributes.inspect}"
      @latest_watchdog_received = Server.now_object
      acknowledged message
    end

    def process packet
      message = Message.parse packet
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
          puts "#{prefix} Received #{message.attributes["type"]}: #{message.attributes.inspect}"
          acknowledged message
        else
          puts "#{prefix} Received unknown message (#{message.attributes["type"]}): #{message.attributes.inspect}"
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
        "oMId" => message.attributes["mId"],
        "rea" => reason || "Unknown reason"
      })
      send message
    end

    def prefix
      "#{Server.now_string} #{@info[:id].to_s.rjust(3)}"
    end

  end

end