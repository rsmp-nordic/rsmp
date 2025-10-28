module RSMP
  # RSMP component
  class Component < ComponentBase
    def initialize(node:, id:, ntsoid: nil, xnid: nil, grouped: false)
      super
    end

    def handle_command(command_code, _arg)
      raise UnknownCommand, "Command #{command_code} not implemented by #{self.class}"
    end

    def get_status(status_code, status_name = nil, _options = {})
      raise UnknownStatus, "Status #{status_code}/#{status_name} not implemented by #{self.class}"
    end

    def acknowledge_alarm(alarm_code)
      alarm = get_alarm_state alarm_code
      if alarm.acknowledge
        log "Acknowledging alarm #{alarm_code}", level: :info
        @node.alarm_acknowledged alarm
      else
        log "Alarm #{alarm_code} already acknowledged", level: :info
      end
    end

    def suspend_alarm(alarm_code)
      alarm = get_alarm_state alarm_code
      if alarm.suspend
        log "Suspending alarm #{alarm_code}", level: :info
        @node.alarm_suspended_or_resumed alarm
      else
        log "Alarm #{alarm_code} already suspended", level: :info
      end
    end

    def resume_alarm(alarm_code)
      alarm = get_alarm_state alarm_code
      if alarm.resume
        log "Resuming alarm #{alarm_code}", level: :info
        @node.alarm_suspended_or_resumed alarm
      else
        log "Alarm #{alarm_code} already resumed", level: :info
      end
    end

    def activate_alarm(alarm_code)
      alarm = get_alarm_state alarm_code
      return unless alarm.activate

      log "Activating alarm #{alarm_code}", level: :info
      @node.alarm_activated_or_deactivated alarm
    end

    def deactivate_alarm(alarm_code)
      alarm = get_alarm_state alarm_code
      return unless alarm.deactivate

      log "Deactivating alarm #{alarm_code}", level: :info
      @node.alarm_activated_or_deactivated alarm
    end

    def status_updates_sent; end
  end
end
