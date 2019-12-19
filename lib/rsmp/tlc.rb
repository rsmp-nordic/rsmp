# Simulates a Traffic Light Controller

module RSMP
  class Tlc < Site

    def initialize options={}
      super options
      @sxl = 'traffic_light_controller'
      @plan = 0
    end

    def handle_command command_code, arg
      case command_code
      when 'M0001'
        handle_m0001 arg
      when 'M0002'
        handle_m0002 arg
      else
        raise UnknownCommand.new "Unknown command #{command_code}"
      end
    end

    def handle_m0001 arg
      arg
    end

    def handle_m0002 arg
      verify_security_code arg['securityCode']
      if arg['status'] = 'True'
        switch_plan arg['timeplan']
      else
        switch_plan 0   # TODO use clock/calender
      end
      arg
    end

    def switch_plan plan
      log "Switching to plan #{plan}", level: :info
      @plan = plan.to_i
      plan
    end

    def get_status status_code, status_name
      return @plan.to_s, "recent"
    end

    def verify_security_code code
    end

  end
end