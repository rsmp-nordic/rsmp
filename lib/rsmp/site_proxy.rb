# Handles a supervisor connection to a remote client

module RSMP  
  class SiteProxy < Proxy
    include SiteBase

    attr_reader :supervisor, :site_id

    def initialize options
      super options
      initialize_site
      @supervisor = options[:supervisor]
      @settings = @supervisor.supervisor_settings.clone
      @site_id = nil
    end

    def node
      supervisor
    end

    def start
      super
      start_reader
    end

    def connection_complete
      super
      log "Connection to site #{@site_id} established", level: :info
    end

    def process_message message
      case message
        when CommandRequest
        when StatusRequest
        when StatusSubscribe
        when StatusUnsubscribe
          will_not_handle message
        when AggregatedStatus
          process_aggregated_status message
        when Alarm
          process_alarm message
        when CommandResponse
          process_command_response message
        when StatusResponse
          process_status_response message
        when StatusUpdate
          process_status_update message
        else
          super message
      end
    end

    def process_deferred
      supervisor.process_deferred
    end

    def version_accepted message
      log "Received Version message for site #{@site_id} using RSMP #{@rsmp_version}", message: message, level: :log
      start_timer
      acknowledge message
      send_version @site_id, @settings['rsmp_versions']
      @version_determined = true

      if @settings['sites']
        @site_settings = @settings['sites'][@site_id]
        @site_settings =@settings['sites'][:any] unless @site_settings
        if @site_settings
          setup_components @site_settings['components']
        end
      end
    end

    def validate_aggregated_status  message, se
      unless se && se.is_a?(Array) && se.size == 8
        reason = "invalid AggregatedStatus, 'se' must be an Array of size 8"
        dont_acknowledge message, "Received", reaons
        raise InvalidMessage
      end
    end

    def process_aggregated_status message
      se = message.attribute("se")
      validate_aggregated_status(message,se) == false
      c_id = message.attributes["cId"]
      component = @components[c_id]
      if component == nil
        if @site_settings == nil || @site_settings['components'] == nil
          component = build_component(id:c_id, type:nil)
          @components[c_id] = component
          log "Adding component #{c_id} to site #{@site_id}", level: :info
        else
          reason = "component #{c_id} not found"
          dont_acknowledge message, "Ignoring #{message.type}:", reason
          return
        end
      end

      component.set_aggregated_status_bools se
      log "Received #{message.type} status for component #{c_id} [#{component.aggregated_status.join(', ')}]", message: message
      acknowledge message
    end

    def aggrated_status_changed component
      @supervisor.aggregated_status_changed self, component
    end

    def process_alarm message
      alarm_code = message.attribute("aCId")
      asp = message.attribute("aSp")
      status = ["ack","aS","sS"].map { |key| message.attribute(key) }.join(',')
      log "Received #{message.type}, #{alarm_code} #{asp} [#{status}]", message: message, level: :log
      acknowledge message
    end

    def version_acknowledged
      connection_complete
    end

    def process_watchdog message
      super
      if @watchdog_started == false
        start_watchdog
      end
    end

    def site_ids_changed
      @supervisor.site_ids_changed
    end

    def request_status component, status_list, timeout=nil
      raise NotReady unless @state == :ready
      message = RSMP::StatusRequest.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => status_list
      })
      send_message message
      return message, wait_for_status_response(message: message, timeout: timeout)
    end

    def process_status_response message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def wait_for_status_response options
      raise ArgumentError unless options[:message]
      item = @archive.capture(@task, options.merge(
        type: ['StatusResponse','MessageNotAck'],
        with_message: true,
        num: 1
      )) do |item|
        if item[:message].type == 'MessageNotAck'
          next item[:message].attribute('oMId') == options[:message].m_id
        elsif item[:message].type == 'StatusResponse'
          next item[:message].attribute('cId') == options[:message].attribute('cId')
        end
      end
      item[:message] if item
    end

    def subscribe_to_status component, status_list, timeout
      raise NotReady unless @state == :ready
      message = RSMP::StatusSubscribe.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => status_list
      })
      send_message message
      return message, wait_for_status_update(component: component, timeout: timeout)[:message]
    end

    def unsubscribe_to_status component, status_list
      raise NotReady unless @state == :ready
      message = RSMP::StatusUnsubscribe.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "sS" => status_list
      })
      send_message message
      message
    end

    def process_status_update message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def wait_for_status_update options={}
      raise ArgumentError.new("component argument is missing") unless options[:component]
      matching_status = nil
      item = @archive.capture(@task,options.merge(type: "StatusUpdate", with_message: true, num: 1)) do |item|
        # TODO check components
        matching_status = nil
        sS = item[:message].attributes['sS']
        sS.each do |status|
          next if options[:sCI] && options[:sCI] != status['sCI']
          next if options[:n] && options[:n] != status['n']
          next if options[:q] && options[:q] != status['q']
          if options[:s].is_a? Regexp
            next if options[:s] && status['s'] !~ options[:s]
          else
            next if options[:s] && options[:s] != status['s']
          end
          matching_status = status
          break
        end
        matching_status != nil
      end
      if item
        { message: item[:message], status: matching_status }
      end
    end

    def status_match? query, item
      return false if query[:sCI] && query[:sCI] != item['sCI']
      return false if query[:n] && query[:n] != item['n']
      return false if query[:q] && query[:q] != item['q']
      if query[:s].is_a? Regexp
        return false if query[:s] && item['s'] !~ query[:s]
      else
        return false if query[:s] && item['s'] != query[:s]
      end
      true
    end

    def wait_for_status_updates options={}
      raise ArgumentError.new("component argument is missing") unless options[:component]
      raise ArgumentError.new("status_list argument is missing") unless options[:status_list]
      want = options[:status_list].clone
      got = {}
      # wait for a status update
      item = @archive.capture(@task,options.merge(type: "StatusUpdate", with_message: true, num: 1)) do |item|
        found = []
        # look through querues
        want.each_with_index do |query,i|
          # look through status items in message
          item[:message].attributes['sS'].each do |input|
            ok = status_match? query, input
            if ok
              got[query] = input
              found << i   # record which queries where matched succesfully
            end
          end
        end
        # remove queries that where matched
        found.sort.reverse.each do |i|
          want.delete_at i
        end
        want.empty? # any queries left to match?
      end
      got
    end

    def wait_for_alarm options={}
      raise ArgumentError.new("component argument is missing") unless options[:component]
      matching_alarm = nil
      item = @archive.capture(@task,options.merge(type: "Alarm", with_message: true, num: 1)) do |item|
        # TODO check components
        matching_alarm = nil
        alarm = item[:message]
        next if options[:aCId] && options[:aCId] != alarm.attribute("aCId")
        next if options[:aSp] && options[:aSp] != alarm.attribute("aSp")
        next if options[:aS] && options[:aS] != alarm.attribute("aS")
        matching_alarm = alarm
        break
      end
      if item
        { message: item[:message], status: matching_alarm }
      end
    end

    def send_alarm_acknowledgement component, alarm_code
      message = RSMP::AlarmAcknowledged.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "aCId" => alarm_code,
          "xACId" => '',
          "xNACId" => '',
          "aSp" => 'Acknowledge'
      })
      send_message message
      message
    end

    def wait_for_alarm_acknowledgement_response options
      raise ArgumentError.new("component argument is missing") unless options[:component]
      item = @archive.capture(@task,options.merge(
        num: 1,
        type: ['AlarmAcknowledgedResponse','MessageNotAck'],
        with_message: true
      )) do |item|
        if item[:message].type == 'MessageNotAck'
          next item[:message].attribute('oMId') == options[:message].m_id
        elsif item[:message].type == 'AlarmAcknowledgedResponse'
          next item[:message].attribute('cId') == options[:message].attribute('cId')
        end
      end
      item[:message] if item
    end

    def send_command component, args
      raise NotReady unless @state == :ready
      message = RSMP::CommandRequest.new({
          "ntsOId" => '',
          "xNId" => '',
          "cId" => component,
          "arg" => args
      })
      send_message message
      message
    end

    def process_command_response message
      log "Received #{message.type}", message: message, level: :log
      acknowledge message
    end

    def command_match? query, item
      return false if query[:sCI] && query[:sCI] != item['sCI']
      return false if query[:n] && query[:n] != item['n']
      if query[:s].is_a? Regexp
        return false if query[:v] && item['v'] !~ query[:v]
      else
        return false if query[:v] && item['v'] != query[:v]
      end
      true
    end

    def wait_for_command_responses options={}
      raise ArgumentError.new("request argument is missing") unless options[:request]
      raise ArgumentError.new("component argument is missing") unless options[:component]
      raise ArgumentError.new("command_list argument is missing") unless options[:command_list]
      want = options[:command_list].clone
      got = {}
      # wait for a command response
      item = @archive.capture(@task,options.merge({
        type: ['CommandResponse'],
        with_message: true,
        num: 1
      })) do |item|
        found = []
        # look through querues
        want.each_with_index do |query,i|
          # look through status items in message
          item[:message].attributes['rvs'].each do |input|
            ok = command_match? query, input
            if ok
              got[query] = input
              found << i   # record which queries where matched succesfully
            end
          end
        end
        # remove queries that where matched
        found.sort.reverse.each do |i|
          want.delete_at i
        end
        want.empty? # any queries left to match?
        end
      got
    end

    def set_watchdog_interval interval
      @settings["watchdog_interval"] = interval
    end

    def check_sxl_version message
      # store sxl version requested by site
      # TODO should check agaist site settings
      @site_sxl_version = message.attribute 'SXL'
    end

    def sxl_version
      # a supervisor does not maintain it's own sxl version
      # instead we use what the site requests
      @site_sxl_version
    end

    def process_version message
      return extraneous_version message if @version_determined
      check_site_ids message
      check_rsmp_version message
      check_sxl_version message
      version_accepted message
    end

    def check_site_ids message
      # RSMP support multiple site ids. we don't support this yet. instead we use the first id only
      site_id = message.attribute("siteId").map { |item| item["sId"] }.first
      @supervisor.check_site_id site_id
      @site_id = site_id
      site_ids_changed
    end

  end
end
