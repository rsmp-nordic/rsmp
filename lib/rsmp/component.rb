module RSMP

  # RSMP component

  class Component < ComponentBase
    def initialize node:, id:, grouped: false
      super
    end

    def handle_command command_code, arg
      raise UnknownCommand.new "Command #{command_code} not implemented by #{self.class}"
    end

    def get_status status_code, status_name=nil
      raise UnknownStatus.new "Status #{status_code}/#{status_name} not implemented by #{self.class}"
    end

    def get_alarm_state alarm_code
      alarm = @alarms[alarm_code] ||= RSMP::AlarmState.new component_id: c_id, code: alarm_code
    end

    def suspend_alarm alarm_code
      alarm_state = get_alarm_state alarm_code
      if alarm.suspended == false
        log "Suspending alarm #{alarm_code}", level: :info
        alarm.suspend
        @node.alarm_suspended_or_resumed alarm
      else
        log "Alarm #{alarm_code} already suspended", level: :info
      end
    end

    def resume_alarm alarm_code
      alarm_state = get_alarm_state alarm_code
      if alarm.suspended
        log "Resuming alarm #{alarm_code}", level: :info
        alarm.resume
        @node.alarm_suspended_or_resumed alarm
      else
        log "Alarm #{alarm_code} not suspended", level: :info
      end
    end

    # send alarm
    def send_alarm code:, status:
      @node.alarm_changed self, alarm
    end

  end
end