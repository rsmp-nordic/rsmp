module RSMP
  # class that tracks the state of an alarm
  class AlarmState
    attr_reader :component_id, :code, :acknowledged, :suspended, :active, :timestamp, :category, :priority

    def initialize component_id:, code:
      @component_id = component_id
      @code = code
      @acknowledged = false
      @suspended = false
      @active = false
      @timestamp = nil
      @category = nil
      @priority = nil
    end

    def suspend
      @suspended = true
    end

    def resume
      @suspended = false
    end

    def activate
      @active = true
    end

    def deactivate
      @active = false
    end
  end
end
