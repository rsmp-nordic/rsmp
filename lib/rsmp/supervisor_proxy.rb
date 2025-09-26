# Handles a site connection to a remote supervisor

require 'digest'

module RSMP
  class SupervisorProxy < Proxy
    attr_reader :supervisor_id, :site

    def initialize(options)
      super(options.merge(node: options[:site]))
      @site = options[:site]
      @site_settings = @site.site_settings.clone
      @ip = options[:ip]
      @port = options[:port]
      @status_subscriptions = {}
      @sxl = @site_settings['sxl']
      @synthetic_id = Supervisor.build_id_from_ip_port @ip, @port
    end

    # handle communication
    # if disconnected, then try to reconnect
    def run
      loop do
        connect
        start_reader
        start_handshake
        wait_for_reader # run until disconnected
        break if reconnect_delay == false
      rescue Restart
        @logger.mute @ip, @port
        raise
      rescue RSMP::ConnectionError => e
        log e, level: :error
        break if reconnect_delay == false
      rescue StandardError => e
        distribute_error e, level: :internal
        break if reconnect_delay == false
      ensure
        close
        stop_subtasks
      end
    end

    def start_handshake
      send_version @site_settings['site_id'], core_versions
    end

    # connect to the supervisor and initiate handshake supervisor
    def connect
      log "Connecting to supervisor at #{@ip}:#{@port}", level: :info
      set_state :connecting
      connect_tcp
      @logger.unmute @ip, @port
      log "Connected to supervisor at #{@ip}:#{@port}", level: :info
    rescue SystemCallError => e
      raise ConnectionError, "Could not connect to supervisor at #{@ip}:#{@port}: Errno #{e.errno} #{e}"
    rescue StandardError => e
      raise ConnectionError, "Error while connecting to supervisor at #{@ip}:#{@port}: #{e}"
    end

    def stop_task
      super
      @last_status_sent = nil
    end

    def connect_tcp
      @endpoint = IO::Endpoint.tcp(@ip, @port)

      # this timeout is a workaround for connect hanging on windows if the other side is not present yet
      timeout = @site_settings.dig('timeouts', 'connect') || 1.1
      task.with_timeout timeout do
        @socket = @endpoint.connect
      end
      delay = @site_settings.dig('intervals', 'after_connect')
      task.sleep delay if delay

      @stream = IO::Stream::Buffered.new(@socket)
      @protocol = RSMP::Protocol.new(@stream) # rsmp messages are json terminated with a form-feed
      set_state :connected
    rescue Errno::ECONNREFUSED => e # rescue to avoid log output
      log 'Connection refused', level: :warning
      raise e
    end

    def handshake_complete
      sanitized_sxl_version = RSMP::Schema.sanitize_version(sxl_version)
      log "Connection to supervisor established, using core #{@core_version}, #{sxl} #{sanitized_sxl_version}",
          level: :info
      set_state :ready
      start_watchdog
      if @site_settings['send_after_connect']
        send_all_aggregated_status
        send_active_alarms
      end
      super
    end

    def process_message(message)
      case message
      when StatusResponse, StatusUpdate, AggregatedStatus, AlarmIssue
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
      when Alarm, AlarmAcknowledged, AlarmSuspend, AlarmResume, AlarmRequest
        process_alarm message
      else
        super
      end
    rescue UnknownComponent, UnknownCommand, UnknownStatus,
           MessageRejected, MissingAttribute => e
      dont_acknowledge message, '', e.to_s
    end

    def acknowledged_first_ingoing(message)
      case message.type
      when 'Watchdog'
        handshake_complete
      end
    end

    def send_all_aggregated_status
      @site.components.each_pair do |_c_id, component|
        send_aggregated_status component if component.grouped
      end
    end

    def send_active_alarms
      @site.components.each_pair do |_c_id, component|
        component.alarms.each_pair do |_alarm_code, alarm_state|
          if alarm_state.active
            alarm = AlarmIssue.new(alarm_state.to_hash.merge('aSp' => 'Issue'))
            send_message alarm
          end
        end
      end
    end

    def reconnect_delay
      return false if @site_settings['intervals']['reconnect'] == :no

      interval = @site_settings['intervals']['reconnect']
      log "Will try to reconnect again every #{interval} seconds...", level: :info
      @logger.mute @ip, @port
      @task.sleep interval
      true
    end

    def version_accepted(message)
      log "Received Version message, using RSMP #{@core_version}", message: message, level: :log
      start_timer
      acknowledge message
      @version_determined = true
      send_watchdog
    end

    def send_aggregated_status(component, options = {})
      m_id = options[:m_id] || RSMP::Message.make_m_id

      # For core <=3.1.2, se items must be send as strings
      # For core > 3.1.2, se items must be send as booleans
      se = if Proxy.version_meets_requirement?(core_version, '<=3.1.2')
             component.aggregated_status_bools.map { |bool| bool ? 'true' : 'false' }
           else
             component.aggregated_status_bools
           end

      message = AggregatedStatus.new({
                                       'aSTS' => clock.to_s,
                                       'cId' => component.c_id,
                                       'fP' => nil,
                                       'fS' => nil,
                                       'se' => se,
                                       'mId' => m_id
                                     })

      set_nts_message_attributes message
      send_and_optionally_collect message, options do |collect_options|
        Collector.new self, collect_options.merge(task: @task, type: 'MessageAck')
      end
    end

    def send_alarm(_component, alarm, options = {})
      send_and_optionally_collect alarm, options do |collect_options|
        Collector.new self, collect_options.merge(task: @task, type: 'MessageAck')
      end
    end

    def process_aggregated_status(message)
      se = message.attribute('se')
      validate_aggregated_status(message, se)
      on = set_aggregated_status se
      log "Received #{message.type} status [#{on.join(', ')}]", message: message, level: :log
      acknowledge message
    end

    def process_alarm(message)
      case message
      when AlarmAcknowledge
        handle_alarm_acknowledge message
      when AlarmSuspend
        handle_alarm_suspend message
      when AlarmResume
        handle_alarm_resume message
      when AlarmRequest
        handle_alarm_request message
      else
        dont_acknowledge message, 'Invalid alarm message type'
      end
    end

    # handle incoming alarm acknowledge
    def handle_alarm_acknowledge(message)
      component_id = message.attributes['cId']
      component = @site.find_component component_id
      alarm_code = message.attribute('aCId')
      log "Received #{message.type} #{alarm_code} acknowledgement", message: message, level: :log
      acknowledge message
      component.acknowledge_alarm alarm_code
    end

    # handle incoming alarm suspend
    def handle_alarm_suspend(message)
      component_id = message.attributes['cId']
      component = @site.find_component component_id
      alarm_code = message.attribute('aCId')
      log "Received #{message.type} #{alarm_code} suspend", message: message, level: :log
      acknowledge message
      component.suspend_alarm alarm_code
    end

    # handle incoming alarm resume
    def handle_alarm_resume(message)
      component_id = message.attributes['cId']
      component = @site.find_component component_id
      alarm_code = message.attribute('aCId')
      log "Received #{message.type} #{alarm_code} resume", message: message, level: :log
      acknowledge message
      component.resume_alarm alarm_code
    end

    # reorganize rmsp command request arg attribute:
    # [{"cCI":"M0002","cO":"setPlan","n":"status","v":"True"},{"cCI":"M0002","cO":"setPlan","n":"securityCode","v":"5678"},{"cCI":"M0002","cO":"setPlan","n":"timeplan","v":"3"}]
    # into the simpler, but equivalent:
    # {"M0002"=>{"status"=>"True", "securityCode"=>"5678", "timeplan"=>"3"}}
    def simplify_command_requests(arg)
      sorted = {}
      arg.each do |item|
        sorted[item['cCI']] ||= {}
        sorted[item['cCI']][item['n']] = item['v']
      end
      sorted
    end

    def process_aggregated_status_request(message)
      log "Received #{message.type}", message: message, level: :log
      component_id = message.attributes['cId']
      component = @site.find_component component_id
      acknowledge message
      send_aggregated_status component
    end

    def process_command_request(message)
      component_id = message.attributes['cId']

      rvs = message.attributes['arg'].map do |item|
        item = item.dup.merge('age' => 'recent')
        item.delete 'cO'
        item
      end

      begin
        component = @site.find_component component_id
        commands = simplify_command_requests message.attributes['arg']
        commands.each_pair do |command_code, arg|
          component.handle_command command_code, arg
        end
        log "Received #{message.type}", message: message, level: :log
      rescue UnknownComponent
        log "Received #{message.type} with unknown component id '#{component_id}' and cannot infer type",
            message: message, level: :warning
        # If the component is unknown, we must set age=undefined for all items,
        # while still acknowledge the message.
        # See https://github.com/rsmp-nordic/rsmp_validator/issues/271
        rvs.map do |item|
          item['age'] = 'undefined'
        end
      end

      response = CommandResponse.new({
                                       'cId' => component_id,
                                       'cTS' => clock.to_s,
                                       'rvs' => rvs
                                     })
      set_nts_message_attributes response
      acknowledge message
      send_message response
    end

    def rsmpify_value(v, q)
      if v.is_a?(Array) || v.is_a?(Set)
        v
      elsif %w[undefined unknown].include?(q.to_s)
        nil
      else
        v.to_s
      end
    end

    def process_status_request(message, options = {})
      ss = []
      begin
        component_id = message.attributes['cId']
        component = @site.find_component component_id
        ss = message.attributes['sS'].map do |arg|
          value, quality = component.get_status arg['sCI'], arg['n'], { sxl_version: sxl_version }
          { 's' => rsmpify_value(value, quality), 'q' => quality.to_s }.merge arg
        end
        log "Received #{message.type}", message: message, level: :log
      rescue UnknownComponent
        log "Received #{message.type} with unknown component id '#{component_id}' and cannot infer type",
            message: message, level: :warning
        # If the component is unknown, we must set q=undefined and s=nil for all items,
        # while still acknowledge the message.
        ss = message.attributes['sS'].map do |arg|
          arg.dup.merge('q' => 'undefined', 's' => nil)
        end
      end

      response = StatusResponse.new({
                                      'cId' => component_id,
                                      'sTs' => clock.to_s,
                                      'sS' => ss,
                                      'mId' => options[:m_id]
                                    })

      set_nts_message_attributes response
      acknowledge message
      send_message response
    end

    def process_status_subcribe(message)
      log "Received #{message.type}", message: message, level: :log

      # @status_subscriptions is organized by component/code/name, for example:
      #
      # {"AA+BBCCC=DDDEE002"=>{"S001"=>["number"]}}
      #
      # This is done to make it easy to send a single status update
      # for each component, containing all the requested statuses

      update_list = {}
      component_id = message.attributes['cId']
      @status_subscriptions[component_id] ||= {}
      update_list[component_id] ||= {}
      now = Time.now # internal timestamp
      subs = @status_subscriptions[component_id]

      message.attributes['sS'].each do |arg|
        sci = arg['sCI']
        subcription = { interval: arg['uRt'].to_i, last_sent_at: now }
        subs[sci] ||= {}
        subs[sci][arg['n']] = subcription
        update_list[component_id][sci] ||= []
        update_list[component_id][sci] << arg['n']
      end
      acknowledge message
      send_status_updates update_list # send status after subscribing is accepted
    end

    def get_status_subscribe_interval(component_id, sci, n)
      @status_subscriptions.dig component_id, sci, n
    end

    def process_status_unsubcribe(message)
      log "Received #{message.type}", message: message, level: :log
      component = message.attributes['cId']

      subs = @status_subscriptions[component]
      if subs
        message.attributes['sS'].each do |arg|
          sCI = arg['sCI']
          if subs[sCI]
            subs[sCI].delete arg['n']
            subs.delete(sCI) if subs[sCI].empty?
          end
        end
        @status_subscriptions.delete(component) if subs.empty?
      end
      acknowledge message
    end

    def timer(now)
      super
      status_update_timer now if ready?
    end

    def fetch_last_sent_status(component, code, name)
      @last_status_sent&.dig component, code, name
    end

    def store_last_sent_status(message)
      component_id = message.attribute('cId')
      @last_status_sent ||= {}
      @last_status_sent[component_id] ||= {}
      message.attribute('sS').each do |item|
        sCI = item['sCI']
        n = item['n']
        s = item['s']
        @last_status_sent[component_id][sCI] ||= {}
        @last_status_sent[component_id][sCI][n] = s
      end
    end

    def status_update_timer(now)
      update_list = {}
      # go through subscriptons and build a similarly organized list,
      # that only contains what should be send

      @status_subscriptions.each_pair do |component, by_code|
        component_object = @site.find_component component
        by_code.each_pair do |code, by_name|
          by_name.each_pair do |name, subscription|
            current = nil
            should_send = false
            if subscription[:interval].zero?
              # send as soon as the data changes
              if component_object
                current, quality = *(component_object.get_status code, name)
                current = rsmpify_value(current, quality)
              end
              last_sent = fetch_last_sent_status component, code, name
              should_send = true if current != last_sent
            elsif subscription[:last_sent_at].nil? || (now - subscription[:last_sent_at]) >= subscription[:interval]
              # send at regular intervals
              should_send = true
            end
            next unless should_send

            subscription[:last_sent_at] = now
            update_list[component] ||= {}
            update_list[component][code] ||= {}
            update_list[component][code][name] = current
          end
        end
      end
      send_status_updates update_list
    end

    def send_status_updates(update_list)
      now = clock.to_s
      update_list.each_pair do |component_id, by_code|
        component = @site.find_component component_id
        sS = []
        by_code.each_pair do |code, names|
          names.map do |status_name, value|
            if value
              quality = 'recent'
            else
              value, quality = component.get_status code, status_name
            end
            sS << { 'sCI' => code,
                    'n' => status_name,
                    's' => rsmpify_value(value, quality),
                    'q' => quality }
          end
        end
        update = StatusUpdate.new({
                                    'cId' => component_id,
                                    'sTs' => now,
                                    'sS' => sS
                                  })
        set_nts_message_attributes update
        send_message update
        store_last_sent_status update
        component.status_updates_sent
      end
    end

    def sxl_version
      @site_settings['sxl_version'].to_s
    end

    def process_version(message)
      return extraneous_version message if @version_determined

      check_core_version message
      check_sxl_version message
      @site_id = Supervisor.build_id_from_ip_port @ip, @port
      version_accepted message
    end

    def check_sxl_version(message); end

    def main
      @site.main
    end
  end
end
