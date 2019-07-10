# Handles a site connection to a remote supervisor

require_relative 'connector'

module RSMP  
  class SiteConnector < Connector

    attr_reader :supervisor_id, :site, :aggregated_status_bools

    def initialize options
      super options
      @site = options[:site]
      @site_settings = @site.site_settings.clone
      @ip = options[:ip]
      @port = options[:port]
      @aggregated_status_bools = Array.new(8,false)

      @status_subscriptions = {}
      @status_subscriptions_mutex = Mutex.new
    end

    def start
      info "Connecting to superviser at #{@ip}:#{@port}"
      super
      connect
      @logger.continue
      start_reader
      send_version @site_settings["rsmp_versions"]
    rescue Errno::ECONNREFUSED
      error "No connection to supervisor at #{@ip}:#{@port}"
      info "Will try to reconnect again every #{@site.site_settings["reconnect_interval"]} seconds.."
      @logger.pause
    end

    def connect
      return if @socket
      @socket = TCPSocket.open @ip, @port  # connect to supervisor
    end

    def connection_complete
      super
      info "Connection to supervisor established"
      start_watchdog
    end

    def acknowledged_first_ingoing message
      # TODO
      # aggregateds status should only be send for later version of rsmp
      # to handle verison differences, we probably need inherited classes
      case message.type
        when "Watchdog"
          send_aggregated_status
      end
    end

    def reconnect_delay
      interval = @site_settings["reconnect_interval"]
      info "Waiting #{interval} seconds before trying to reconnect"
      sleep interval
    end

    def version_accepted message, rsmp_version
      log "Received Version message for sites [#{@site_ids.join(',')}] using RSMP #{rsmp_version}", message
      start_timer
      acknowledge message
      connection_complete
      @version_determined = true
    end

    def validate_aggregated_status  message, se
      unless se && se.is_a?(Array) && se.size == 8
        reason = 
        dont_acknowledge message, "Received", "invalid AggregatedStatus, 'se' must be an Array of size 8"
        raise InvalidMessage
      end
    end

    def set_aggregated_status se
      keys = [ :local_control,
               :communication_distruption,
               :high_priority_alarm,
               :medium_priority_alarm,
               :low_priority_alarm,
               :normal,
               :rest,
               :not_connected ]

      @aggregated_status_bools = se
      on = []
      keys.each_with_index do |key,index|
        @aggregated_status[key] = se[index]
        on << key if se[index] == true
      end
      on
    end

    def send_aggregated_status
      message = AggregatedStatus.new({
        "aSTS"=>RSMP.now_string,
        "fP"=>nil,
        "fS"=>nil,
        "se"=>@aggregated_status_bools
      })
      send message
    end

    def process_aggregated_status message
      se = message.attribute("se")
      validate_aggregated_status(message,se) == false
      on = set_aggregated_status se
      log "Received #{message.type} status [#{on.join(', ')}]", message
      acknowledge message
    end

    def process_alarm message
      alarm_code = message.attribute("aCId")
      asp = message.attribute("aSp")
      status = ["ack","aS","sS"].map { |key| message.attribute(key) }.join(',')
      log "Received #{message.type}, #{alarm_code} #{asp} [#{status}]", message
      acknowledge message
    end

    def process_command_request message
      log "Received #{message.type}", message
      rvs = []
      message.attributes["arg"].each do |arg|
        rvs << { "cCI": arg["cCI"],
                 "n": arg["n"],
                 "v": arg["v"],
                 "age": "recent" }
      end

      response = CommandResponse.new({
        "cId"=>message.attributes["cId"],
        "cTS"=>RSMP.now_string,
        "rvs"=>rvs
      })
      acknowledge message
      send response
    end

    def process_status_request message
      log "Received #{message.type}", message
      sS = message.attributes["sS"].clone.map do |request|
        request["s"] = rand(100)
        request["q"] = "recent"
        request
      end
      response = StatusResponse.new({
        "cId"=>message.attributes["cId"],
        "sTs"=>RSMP.now_string,
        "sS"=>sS
      })
      acknowledge message
      send response
    end

    def process_status_subcribe message
      log "Received #{message.type}", message

      # @status_subscriptions is organized by component/code/name, for example:
      #
      # {"AA+BBCCC=DDDEE002"=>{"S001"=>["number"]}}
      #
      # This is done to make it easy to send a single status update
      # for each component, containing all the requested statuses

      update_list = {}

      @status_subscriptions_mutex.synchronize do
        component = message.attributes["cId"]
        
        @status_subscriptions[component] ||= {}    
        update_list[component] ||= {} 

        message.attributes["sS"].each do |arg|
          subcription = {interval: arg["uRt"].to_i, last_sent_at: nil}
          @status_subscriptions[component][arg["sCI"]] ||= {}
          @status_subscriptions[component][arg["sCI"]][arg["n"]] = subcription

          update_list[component][arg["sCI"]] ||= []
          update_list[component][arg["sCI"]] << arg["n"]
        end
      end
      acknowledge message
      send_status_updates update_list   # send status after subscribing is accepted
    end

    def process_status_unsubcribe message
      log "Received #{message.type}", message
      component = message.attributes["cId"]

      if @status_subscriptions[component]
        @status_subscriptions_mutex.synchronize do
           message.attributes["sS"].each do |arg|
            if @status_subscriptions[component][arg["sCI"]]
              @status_subscriptions[component][arg["sCI"]].delete arg["n"]
            end
            if @status_subscriptions[component][arg["sCI"]].empty?
              @status_subscriptions[component].delete(arg["sCI"])
            end
          end
          if @status_subscriptions[component].empty?
            @status_subscriptions.delete(component)
          end
        end
      end
      acknowledge message
    end

    def timer now
      super
      status_update_timer now if ready?
    end

    def status_update_timer now
      update_list = {}
      @status_subscriptions_mutex.synchronize do
        # go through subscriptons and build a similarly organized list,
        # that only contains what should be send

        @status_subscriptions.each_pair do |component,by_code|
          by_code.each_pair do |code,by_name|
            by_name.each_pair do |name,subscription|
              if subscription[:interval] == 0 
                # send as soon as the data changes
                if rand(100) >= 90
                  should_send = true
                end
              else
                # send at regular intervals
                if subscription[:last_sent_at] == nil || (now - subscription[:last_sent_at]) >= subscription[:interval]
                  should_send = true
                end
              end
              if should_send
                subscription[:last_sent_at] = now
                update_list[component] ||= {}
                update_list[component][code] ||= []
                update_list[component][code] << name
             end
            end
          end
        end
      end
      send_status_updates update_list
    rescue StandardError => e
      error ["Status update exception: #{e}",e.backtrace].flatten.join("\n")
    end

    def send_status_updates update_list
      now = RSMP.now_string
      update_list.each_pair do |component,by_code|
        sS = []
        by_code.each_pair do |code,names|
          names.each do |name|
            sS << { "sCI": code,
                     "n": name,
                     "s": rand(100),
                     "q": "recent" }
          end
        end
        update = StatusUpdate.new({
          "cId"=>component,
          "sTs"=>now,
          "sS"=>sS
        })
        send update
      end
    end

  end
end