# Simulates a Traffic Light Controller

module RSMP

  class TrafficController < Component
    attr_reader :pos, :cycle_time
    def initialize node:, id:, cycle_time:
      super node: node, id: id, grouped: true
      @pos = 0
      @cycle_time = cycle_time
      @signal_groups = []
      @plan = 0
      @dark_mode = 'False'
      @yellow_flash = 'False'
      @booting = 'False'
      @police_key = 0
    end

    def add_signal_group group
      @signal_groups << group
    end

    def timer now
      pos = now.to_i % @cycle_time
      if pos != @pos
        @pos = pos
        move pos
      end
    end

    def move pos
      @signal_groups.each do |group|
        group.move pos
      end
      output_states

      if pos == 0
        aggrated_status_changed
      end
    end

    def output_states
      #out = "#{pos} "
      #@signal_groups.each do |group|
      #  out << "#{group.c_id}#{group.state} "
      #end
      #print "\t#{out}\r"
      print "\t#{pos.to_s.ljust(3)} #{format_signal_group_status}\r"
    end

    def format_signal_group_status
      @signal_groups.map { |group|group.state }.join
    end

    def handle_command command_code, arg
      case command_code
      when 'M0001'
        handle_m0001 arg
      when 'M0002'
        handle_m0002 arg
      when 'M0007'
        handle_m0007 arg
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

    def handle_m0007 arg
      verify_security_code arg['securityCode']
      set_fixed_time_control arg['status']
      arg
    end

    def set_fixed_time_control status
      @fixed_time_control = status
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
        return format_signal_group_status, "recent"
      when 'S0005'
        return @booting, "recent"
      when 'S0007'
        if @dark_mode == 'True'
          return 'False', "recent"
        else
          return 'True', "recent"
        end
      when 'S0009'
        return @fixed_time_control.to_s, "recent"
      when 'S0013'
        return @police_key.to_s, "recent"
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

  class SignalGroup < Component
    attr_reader :plan, :state

    def initialize node:, id:, plan:
      super node: node, id: id, grouped: false
      @plan = plan
      move 0
    end

    def get_state pos
      if pos > @plan.length
        '.'
      else
        @plan[pos]
      end
    end

    def move pos
      @state = get_state pos
    end
  end

  class Tlc < Site
    def initialize options={}
      super options

      @sxl = 'traffic_light_controller'

      unless @main
        raise ConfigurationError.new "TLC must have a main component"
      end
    end

    def build_component id, settings={}
      component = case settings['type']
      when 'main'
        @main = TrafficController.new node: self, id: id, cycle_time: settings['cycle_time']
      when 'signal_group'
        group = SignalGroup.new node: self, id: id, plan: settings['plan']
        @main.add_signal_group group
        group
      end
    end

    def start_action
      super
      start_timer
    end

    def start_timer
      name = "tlc timer"
      interval = 1 #@settings["timer_interval"] || 1
      log "Starting #{name} with interval #{interval} seconds", level: :debug

      @timer = @task.async do |task|
        task.annotate "timer"
        next_time = Time.now.to_f
        loop do
          now = RSMP.now_object
          break if timer(now) == false
        rescue StandardError => e
          log ["#{name} exception: #{e}",e.backtrace].flatten.join("\n"), level: :error
        ensure
          # adjust sleep duration to avoid drift. so wake up always happens on the 
          # same fractional second.
          # note that Time.now is not monotonic. If the clock si changed,
          # either manaully or via NTP, the sleep interval might jump.
          # an alternative is to use ::Process.clock_gettime(::Process::CLOCK_MONOTONIC),
          # to get the current time. this ensures a constant interval, but
          # if the clock is changed, the wake up would then happen on a different 
          # fractional second

          next_time += interval
          duration = next_time - Time.now.to_f
          task.sleep duration
        end
      end
    end

    def timer now
      return unless @main
      @main.timer now
    end

    def handle_command command_code, arg
      return unless @main
      @main.handle_command command_code, arg
    end

    def get_status status_code, status_name=nil
      return unless @main
      @main.get_status status_code, status_name
    end

  end
end