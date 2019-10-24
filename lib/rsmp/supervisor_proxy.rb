# Handles a site connection to a remote supervisor

module RSMP  
  class SupervisorProxy < Proxy

    attr_reader :supervisor_id, :site

    def initialize options
      super options
      @site = options[:site]
      @site_settings = @site.site_settings.clone
      @ip = options[:ip]
      @port = options[:port]
      @status_subscriptions = {}
      @status_subscriptions_mutex = Mutex.new
    end

    def start
      info "Connecting to superviser at #{@ip}:#{@port}"
      super
      connect
      @logger.unmute @ip, @port
      start_reader
      send_version @site_settings["rsmp_versions"]
    rescue Errno::ECONNREFUSED
      error "No connection to supervisor at #{@ip}:#{@port}"
      info "Will try to reconnect again every #{@site.site_settings["reconnect_interval"]} seconds.."
      @logger.mute @ip, @port
    end

    def connect
      return if @socket
      @endpoint = Async::IO::Endpoint.tcp(@ip, @port)
      @socket = @endpoint.connect
      @stream = Async::IO::Stream.new(@socket)
      @protocol = Async::IO::Protocol::Line.new(@stream,"\f") # rsmp messages are json terminated with a form-feed
    end

    def connection_complete
      super
      info "Connection to supervisor established"
      start_watchdog
    end

    def process_message message
      case message
        when Alarm
        when StatusResponse
        when StatusUpdate
        when AggregatedStatus
          will_not_handle message
        when CommandRequest
          process_command_request message
        when CommandResponse
          process_command_response message
        when StatusRequest
          process_status_request message
        when StatusSubscribe
          process_status_subcribe message
        when StatusUnsubscribe
          process_status_unsubcribe message
        else
          super message
      end
    end

    def acknowledged_first_ingoing message
      # TODO
      # aggregateds status should only be send for later version of rsmp
      # to handle verison differences, we probably need inherited classes
      case message.type
        when "Watchdog"
          send_all_aggregated_status
      end
    end

    def send_all_aggregated_status
      @site.components.each_pair do |c_id,component|
        if component.grouped
          send_aggregated_status component
        end
      end
    end

    def reconnect_delay
      interval = @site_settings["reconnect_interval"]
      info "Waiting #{interval} seconds before trying to reconnect"
      @task.sleep interval
    end

    def version_accepted message, rsmp_version
      log "Received Version message, using RSMP #{rsmp_version}", message
      start_timer
      acknowledge message
      connection_complete
      @version_determined = true
    end

    def send_aggregated_status component
      message = AggregatedStatus.new({
        "aSTS" => RSMP.now_string,
        "cId" =>  component.c_id,
        "fP" => nil,
        "fS" => nil,
        "se" => component.aggregated_status_bools
      })
      send message
    end

    def process_command_request message
      log "Received #{message.type}", message
      rvs = []
      message.attributes["arg"].each do |arg|
        unless arg['cCI'] && arg['n'] && arg['v']
          dont_acknowledge message, '', 'bad arguments'
          return
        end 
        rvs << { "cCI" => arg["cCI"],
                 "n" => arg["n"],
                 "v" => arg["v"],
                 "age" => "recent" }
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
      acknowledge message
      send_status_updates update_list   # send status after subscribing is accepted
    end

    def process_status_unsubcribe message
      log "Received #{message.type}", message
      component = message.attributes["cId"]

      if @status_subscriptions[component]
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
      acknowledge message
    end

    def timer now
      super
      status_update_timer now if ready?
    end

    def status_update_timer now
      update_list = {}
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

    def send_alarm
      message = Alarm.new({
        "aSTS"=>RSMP.now_string,
        "fP"=>nil,
        "fS"=>nil,
        "se"=>@site.aggregated_status_bools
      })
      send message
    end

  end
end