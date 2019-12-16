# Handles a site connection to a remote supervisor

require 'digest'

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
      @sxl = @site_settings['sxl']
      @synthetic_id = Supervisor.build_id_from_ip_port @ip, @port
    end

    def node
      site
    end

    def start
      log "Connecting to superviser at #{@ip}:#{@port}", level: :info
      super
      connect
      @logger.unmute @ip, @port
      start_reader
      send_version @site_settings['site_id'], @site_settings["rsmp_versions"]
    rescue Errno::ECONNREFUSED
      log "No connection to supervisor at #{@ip}:#{@port}", level: :error
      unless @site.site_settings["reconnect_interval"] == :no
        log "Will try to reconnect again every #{@site.site_settings["reconnect_interval"]} seconds..", level: :info
        @logger.mute @ip, @port
      end
    end

    def connect
      return if @socket
      @endpoint = Async::IO::Endpoint.tcp(@ip, @port)
      @socket = @endpoint.connect
      @stream = Async::IO::Stream.new(@socket)
      @protocol = Async::IO::Protocol::Line.new(@stream,RSMP::WRAPPING_DELIMITER) # rsmp messages are json terminated with a form-feed
    end

    def connection_complete
      super
      log "Connection to supervisor established", level: :info
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
          if @site_settings['send_after_connect']
            send_all_aggregated_status
          end
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
      log "Waiting #{interval} seconds before trying to reconnect", level: :info
      @task.sleep interval
    end

    def version_accepted message
      log "Received Version message, using RSMP #{@rsmp_version}", message: message, level: :log
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
      send_message message
    end

    def process_aggregated_status message
      se = message.attribute("se")
      validate_aggregated_status(message,se) == false
      on = set_aggregated_status se
      log "Received #{message.type} status [#{on.join(', ')}]", message: message, level: :log
      acknowledge message
    end

    def process_alarm message
      alarm_code = message.attribute("aCId")
      asp = message.attribute("aSp")
      status = ["ack","aS","sS"].map { |key| message.attribute(key) }.join(',')
      log "Received #{message.type}, #{alarm_code} #{asp} [#{status}]", message: message, level: :log
      acknowledge message
    end

    def process_command_request message
      log "Received #{message.type}", message: message, level: :log
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
      send_message response
    end

    def process_status_request message
      component_id = message.attributes["cId"]
      component = @site.find_component component_id

      log "Received #{message.type}", message: message, level: :log
      sS = message.attributes["sS"].clone.map do |request|
        request["s"] = rand(100).to_s
        request["q"] = "recent"
        request
      end
      response = StatusResponse.new({
        "cId"=>component_id,
        "sTs"=>RSMP.now_string,
        "sS"=>sS
      })
      acknowledge message
      send_message response
    rescue UnknownComponent => e
      dont_acknowledge message, '', e.to_s
    end

    def process_status_subcribe message
      log "Received #{message.type}", message: message, level: :log


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

      subs = @status_subscriptions[component]

      message.attributes["sS"].each do |arg|
        sCI = arg["sCI"]
        subcription = {interval: arg["uRt"].to_i, last_sent_at: nil}
        subs[sCI] ||= {}
        subs[sCI][arg["n"]] = subcription

        update_list[component][sCI] ||= []
        update_list[component][sCI] << arg["n"]
      end
      acknowledge message
      send_status_updates update_list   # send status after subscribing is accepted
    end

    def process_status_unsubcribe message
      log "Received #{message.type}", message: message, level: :log
      component = message.attributes["cId"]

      subs = @status_subscriptions[component]
      if subs
        message.attributes["sS"].each do |arg|
          sCI = arg["sCI"]
          if subs[sCI]
            subs[sCI].delete arg["n"]
            subs.delete(sCI) if subs[sCI].empty?
          end
        end
        @status_subscriptions.delete(component) if subs.empty?
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
      log ["Status update exception: #{e}",e.backtrace].flatten.join("\n"), level: :error
    end

    def send_status_updates update_list
      now = RSMP.now_string
      update_list.each_pair do |component,by_code|
        sS = []
        by_code.each_pair do |code,names|
          names.each do |name|
            sS << { "sCI" => code,
                     "n" => name,
                     "s" => rand(100).to_s,
                     "q" => "recent" }
          end
        end
        update = StatusUpdate.new({
          "cId"=>component,
          "sTs"=>now,
          "sS"=>sS
        })
        send_message update
      end
    end

    def send_alarm
      message = Alarm.new({
        "aSTS"=>RSMP.now_string,
        "fP"=>nil,
        "fS"=>nil,
        "se"=>@site.aggregated_status_bools
      })
      send_message message
    end

    def sxl_version
      @site_settings['sxl_version']
    end

    def process_version message
      return extraneous_version message if @version_determined
      check_rsmp_version message
      check_sxl_version message
      @site_id = Supervisor.build_id_from_ip_port @ip, @port
      version_accepted message
    end

    def check_sxl_version message
    end

  end
end