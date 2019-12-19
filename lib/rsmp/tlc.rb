# Simulates a Traffic Light Controller

module RSMP
  class Tlc < Site

    def initialize options={}
      super options
      @sxl = 'traffic_light_controller'
      @plan = 0
      @dark_mode = 'False'
      @yellow_flash = 'False'
      @booting = 'False'

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
      verify_security_code arg['securityCode']
      switch_mode arg['status']
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

   def switch_mode mode
      log "Switching to mode #{mode}", level: :info
      case mode
      when 'NormalControl'
        @yellow_flash = 'False'
        @dark_mode = 'False'
      when 'YellowFlash'
        @yellow_flash = 'True'
        @dark_mode = 'False'
      when 'Dark'
        @yellow_flash = 'False'
        @dark_mode = 'True'
      end
      mode
    end

    def get_status status_code, status_name=nil
      case status_code
      when 'S0001'
        return 'AAAA', "recent"
      when 'S0005'
        return @booting, "recent"
      when 'S0007'
        if @dark_mode == 'True'
          return 'False', "recent"
        else
          return 'True', "recent"
        end
      when 'S0014'
        return @plan.to_s, "recent"
      when 'S0011'
        return @yellow_flash, "recent"
      else
        raise InvalidMessage.new "unknown status code #{status_code}"
      end
    end

    def verify_security_code code
    end

  end
end