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
      log "Connected to superviser at #{@ip}:#{@port}", level: :info
      start_reader
      send_version @site_settings['site_id'], @site_settings["rsmp_versions"]
    rescue Errno::ECONNREFUSED
      log "No connection to supervisor at #{@ip}:#{@port}", level: :error
      unless @site.site_settings["reconnect_interval"] == :no
        log "Will try to reconnect again every #{@site.site_settings["reconnect_interval"]} seconds..", level: :info
        @logger.mute @ip, @port
      end
    end

    def stop
      log "Closing connection to supervisor", level: :info
      super
      @last_status_sent = nil
    end

    def connect
      return if @socket
      @endpoint = Async::IO::Endpoint.tcp(@ip, @port)
      @socket = @endpoint.connect
      @stream = Async::IO::Stream.new(@socket)
      @protocol = Async::IO::Protocol::Line.new(@stream,WRAPPING_DELIMITER) # rsmp messages are json terminated with a form-feed
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
        when AggregatedStatusRequest
          process_aggregated_status_request message
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
    rescue UnknownComponent, UnknownCommand, UnknownStatus,
           MessageRejected, MissingAttribute => e
      dont_acknowledge message, '', e.to_s
    end

    def process_deferred
      site.process_deferred
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
        "aSTS" => clock.to_s,
        "cId" =>  component.c_id,
        "fP" => 'NormalControl',
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

    # reorganize rmsp command request arg attribute:
    # [{"cCI":"M0002","cO":"setPlan","n":"status","v":"True"},{"cCI":"M0002","cO":"setPlan","n":"securityCode","v":"5678"},{"cCI":"M0002","cO":"setPlan","n":"timeplan","v":"3"}]
    # into the simpler, but equivalent:
    # {"M0002"=>{"status"=>"True", "securityCode"=>"5678", "timeplan"=>"3"}}
    def simplify_command_requests arg
      sorted = {}
      arg.each do |item|
        sorted[item['cCI']] ||= {}
        sorted[item['cCI']][item['n']] = item['v']
      end
      sorted
    end

    def process_aggregated_status_request message
      log "Received #{message.type}", message: message, level: :log
      component_id = message.attributes["cId"]
      component = @site.find_component component_id
      acknowledge message
      send_aggregated_status component
    end

    def process_command_request message
      log "Received #{message.type}", message: message, level: :log
      component_id = message.attributes["cId"]
      component = @site.find_component component_id
      commands = simplify_command_requests message.attributes["arg"]
      commands.each_pair do |command_code,arg|
        component.handle_command command_code,arg
      end

      rvs = message.attributes["arg"].map do |item|
        item = item.dup.merge('age'=>'recent')
        item.delete 'cO'
        item
      end
      response = CommandResponse.new({
        "cId"=>component_id,
        "cTS"=>clock.to_s,
        "rvs"=>rvs
      })
      acknowledge message
      send_message response
    end

    def process_status_request message, options={}
      component_id = message.attributes["cId"]
      component = @site.find_component component_id
      log "Received #{message.type}", message: message, level: :log
      sS = message.attributes["sS"].map do |arg|
        value, quality =  component.get_status arg['sCI'], arg['n']
        { "s" => value.to_s, "q" => quality.to_s }.merge arg
      end
      response = StatusResponse.new({
        "cId"=>component_id,
        "sTs"=>clock.to_s,
        "sS"=>sS,
        "mId" => options[:m_id]
      })
      acknowledge message
      send_message response
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
      now = Time.now  # internal timestamp

      message.attributes["sS"].each do |arg|
        sCI = arg["sCI"]
        subcription = {interval: arg["uRt"].to_i, last_sent_at: now}
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

    def fetch_last_sent_status component, code, name
      if @last_status_sent && @last_status_sent[component] && @last_status_sent[component][code]
        @last_status_sent[component][code][name]
      else
        nil
      end
    end

    def store_last_sent_status component, code, name, value
      @last_status_sent ||= {}
      @last_status_sent[component] ||= {}
      @last_status_sent[component][code] ||= {}
      @last_status_sent[component][code][name] = value
    end

    def status_update_timer now
      update_list = {}
      # go through subscriptons and build a similarly organized list,
      # that only contains what should be send

      @status_subscriptions.each_pair do |component,by_code|
        component_object = @site.find_component component
        by_code.each_pair do |code,by_name|
          by_name.each_pair do |name,subscription|
            current = nil
            if subscription[:interval] == 0 
              # send as soon as the data changes
              if component_object
                current, age = *(component_object.get_status code, name)
              end
              last_sent = fetch_last_sent_status component, code, name
              if current != last_sent
                should_send = true
                store_last_sent_status component, code, name, current
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
              update_list[component][code] ||= {}
              update_list[component][code][name] = current
           end
          end
        end
      end
      send_status_updates update_list
    end

    def send_status_updates update_list
      now = clock.to_s
      update_list.each_pair do |component_id,by_code|
        component = @site.find_component component_id
        sS = []
        by_code.each_pair do |code,names|
          names.map do |status_name,value|
            if value
              quality = 'recent'
            else
              value,quality = component.get_status code, status_name
            end
            sS << { "sCI" => code,
                     "n" => status_name,
                     "s" => value.to_s,
                     "q" => quality }
          end
        end
        update = StatusUpdate.new({
          "cId"=>component_id,
          "sTs"=>now,
          "sS"=>sS
        })
        send_message update
      end
    end

    def send_alarm
      message = Alarm.new({
        "aSTS"=>clock.to_s,
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