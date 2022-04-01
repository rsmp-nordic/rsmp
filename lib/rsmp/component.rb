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
      alarm = get_alarm_state alarm_code
      return if alarm.suspended
      log "Suspending alarm #{alarm_code}", level: :info
      alarm.suspend
      @node.alarm_changed alarm
    end

    def resume_alarm alarm_code
      alarm = get_alarm_state alarm_code
      return unless alarm.suspended
      log "Resuming alarm #{alarm_code}", level: :info
      alarm.resume
      @node.alarm_changed alarm
    end

    def activate_alarm alarm_code
      alarm = get_alarm_state alarm_code
      return if alarm.active
      log "Activating alarm #{alarm_code}", level: :info
      alarm.activate
      @node.alarm_changed alarm
    end

    def deactivate_alarm alarm_code
      alarm = get_alarm_state alarm_code
      return unless alarm.active
      log "Deactivating alarm #{alarm_code}", level: :info
      alarm.deactivate
      @node.alarm_changed alarm
    end
  end
end