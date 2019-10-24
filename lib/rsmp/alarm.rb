# RSMP Alarm. Manages the various states an alarm can be in.

module RSMP
  class Alarm

    def initialize code: code, blocked: blocked=false, suspended: suspended=false, acknowledged: acknowledged=false
      @code = code
      @code = code
      @blocked = blocked
      @suspended = suspended
      @acknowledged = acknowledged
    end

  end
end