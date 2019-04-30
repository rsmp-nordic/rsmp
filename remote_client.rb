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
      @verbose = server.settings["verbose"] == true
      @site_ids = []
    end

    def run
      start_reader
      @reader.join
      kill_threads
    end

    def terminate
      log "Closing connection"
      @reader.kill
    end

    def kill_threads
      reaper = Thread.new(@threads) do |threads|
        threads.each do |thread|
          log "Stopping #{thread[:name]}"
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
              log "Read error: #{e}"
              puts e.backtrace
            end
          end
        end
      end
    end

    def start_watchdog
      name = "watchdog"
      interval = @server.settings["watchdog_interval"]
      log "Starting #{name} with interval of #{interval} seconds"
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            message = Watchdog.new( {"wTs" => Server.now_string})
            send message
          rescue StandardError => e
            log "#{name} error: #{e}"
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
      log "Starting #{name} with interval #{interval}"
      @latest_watchdog_received = Server.now_object
      @threads << Thread.new(@client) do |socket|
        Thread.current[:name] = name
        loop do
          begin
            now = Server.now_object
            break if check_ack_timeout now
            break if check_watchdog_timeout now
          rescue StandardError => e
            log "#{name}: #{e}"
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
          log "No acknowledgements for #{data["type"]} within #{timeout} seconds"
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
        log "Did not receive Watchdog within #{timeout} seconds"
        terminate
        true
      end
      false
    end

    def send message, reason=nil
      message.generate_json
      if reason
        log "Sent #{message.type} #{reason}", message
      else
        log "Sent #{message.type}", message
      end
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
        reason = "Received extraneous Version message"
        log "#{reason}", message
        dont_acknowledge message, reason
        return
      end

      check_site_ids message
      rsmp_version = check_rsmp_version message
      #check_sxl_version
      version_accepted message, rsmp_version
    end

    def check_site_ids message
      message.attributes["siteId"].map { |item| item["sId"] }.each do |site_id|
        if check_site_id site_id
          @site_ids << site_id
          log "Site id #{site_id} accepted"
        else
          reason = "Site id #{site_id} rejected"
          log reason
          dont_acknowledge message, reason
          terminate
          return nil
        end
      end
    rescue StandardError => e
      reason = "Bad site id #{e.inspect}"
      log reason
      dont_acknowledge message, reason
      terminate
      return nil
    end

    def check_site_id site_id
      true
    end

    def check_rsmp_version message
      # find versions that both we and the client support
      candidates = message.versions & @server.rsmp_versions
      if candidates.any?
        # pick latest version
        version = candidates.sort.last
        log "Received Version, using #{version}", message
        return version
      else
        reason = "RSMP versions [#{message.versions.join(',')}] were requested, but we only support [#{@server.rsmp_versions.join(',')}]."
        dont_acknowledge message, reason
        terminate
        return nil
      end
    end

    def version_accepted message, rsmp_version
      start_timeout
      acknowledge message
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
      past_item = @awaiting_acknowledgement[ message.attributes["oMId"] ]
      if past_item
        log "Received #{message.type} for #{past_item["type"]}", message
      else
        log "Received #{message.type}", message
      end
      got_acknowledgement message
    end

    def process_not_ack message
      log "Received #{message.type}", message
      got_acknowledgement message
    end

    def process_watchdog message
      log "Received #{message.type}", message
      @latest_watchdog_received = Server.now_object
      acknowledge message
    end

    def expect_version_message message
      unless message.is_a? Version
        reason = "Version must be received first, but got #{message.type}"
        log "#{reason}", message
        dont_acknowledge message, reason
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
          log "Received #{message.type}", message
          acknowledge message
        else
          reason = "Received unknown message (#{message.type})"
          log "#{reason}", message
          dont_acknowledge message, reason
      end
    rescue InvalidPacket => e
      log "Received invalid package, size=#{packet.size}, content=#{e.message}"
    rescue InvalidJSON => e
      log "Received invalid JSON"
    rescue InvalidMessage => e
      log "Received invalid message"
    end

    def acknowledge message
      ack = MessageAck.build_from(message)
      send ack, "for #{message.attributes["type"]}"
    end

    def dont_acknowledge message, reason=nil
      message = MessageNotAck.new({
        "oMId" => message.mId,
        "rea" => reason || "Unknown reason"
      })
      send message, "for #{message.attributes["type"]}, #{reason}"
    end

    def prefix
      site_id = @site_ids.first
      "#{Server.log_prefix(@info[:ip])} #{site_id.to_s.ljust(12)}"
    end

    def log str, message=nil
      if @verbose && message
        puts "#{prefix} #{str} #{message.json.to_str}"
      else
        puts "#{prefix} #{str}"
      end
    end
  end
end