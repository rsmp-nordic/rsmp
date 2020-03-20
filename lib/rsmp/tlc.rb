# Simulates a Traffic Light Controller

module RSMP

  class TrafficController < Component
    attr_reader :pos, :cycle_time
    def initialize node:, id:, cycle_time:
      super node: node, id: id, grouped: true
      @signal_groups = []
      @detector_logics = []
      @plans = []
      @pos = 0
      @cycle_time = cycle_time
      @plan = 0
      @dark_mode = false
      @yellow_flash = false
      @booting = false
      @control_mode = 'control'
      @police_key = 0
      @intersection = 0
      @is_starting = false
      @emergency_stage = false
      @emergency_stage_num = 0
      @traffic_situation = 0
      @num_traffic_situations = 1
      @manual_control = false
      @fixed_time_control = false
      @isolated_control = false
      @yellow_flash = false
      @all_red = false
    end

    def add_signal_group group
      @signal_groups << group
    end

    def add_detector_logic logic
      @detector_logics << logic
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
      if pos == 0
        aggrated_status_changed
      end
    end

    def output_states
      str = @signal_groups.map do |group|
        s = "#{group.c_id}:#{group.state}"
        if group.state =~ /^[1-9]$/
          s.colorize(:green)
      elsif group.state =~ /^[NOP]$/
          s.colorize(:yellow)
        else
          s.colorize(:red)
        end
      end.join ' '
      print "\t#{pos.to_s.ljust(3)} #{str}\r"
    end

    def format_signal_group_status
      @signal_groups.map { |group| group.state }.join
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
      if from_rsmp_bool(arg['status'])
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
        @yellow_flash = false
        @dark_mode = false
      when 'YellowFlash'
        @yellow_flash = true
        @dark_mode = false
      when 'Dark'
        @yellow_flash = false
        @dark_mode = true
      end
      mode
    end

    def to_rmsp_bool bool
      if bool
        'True'
      else
        'False'
      end
    end

    def from_rsmp_bool str
      str == 'True'
    end

    def get_status status_code, status_name=nil
      case status_code
      when 'S0001', 'S0002', 'S0003', 'S0004', 'S0005', 'S0006', 'S0007',
           'S0008', 'S0009', 'S0010', 'S0011', 'S0012', 'S0013', 'S0014',
           'S0015', 'S0016', 'S0017', 'S0018', 'S0019', 'S0020', 'S0021',
           'S0022', 'S0023', 'S0024', 'S0025', 'S0026', 'S0027', 'S0028',
           'S0029',
           'S0091', 'S0092', 'S0095', 'S0096',
           'S0201', 'S0202', 'S0203', 'S0204', 'S0205', 'S0206', 'S0207',
           'S0208'
        return send("handle_#{status_code.downcase}", status_code, status_name)
      else
        raise InvalidMessage.new "unknown status code #{status_code}"
      end
    end

    def make_status value, q='recent'
      case value
      when true, false
        return to_rmsp_bool(value), q
      else
        return value, q
      end
    end

    def handle_s0001 status_code, status_name=nil
      case status_name
      when 'signalgroupstatus'
        return make_status format_signal_group_status
      when 'cyclecounter'
        make_status @pos.to_s
      when 'basecyclecounter'
        make_status @pos.to_s
      when 'stage'
        make_status 0.to_s
      end
    end

    def handle_s0002 status_code, status_name=nil
      case status_name
      when 'detectorlogicstatus'
        make_status 0.to_s
      end
    end

    def handle_s0003 status_code, status_name=nil
      case status_name
      when 'inputstatus'
        make_status 0.to_s
      when 'extendedinputstatus'
        make_status 0.to_s
      end
    end

    def handle_s0004 status_code, status_name=nil
      case status_name
      when 'outputstatus'
        make_status 0
      when 'extendedoutputstatus'
        make_status 0
      end
    end

    def handle_s0005 status_code, status_name=nil
      case status_name
      when 'status'
        make_status @is_starting
      end
    end

    def handle_s0006 status_code, status_name=nil
      case status_name
      when 'status'
        make_status @emergency_stage
      when 'emergencystage'
        make_status @emergency_stage_num
      end
    end

    def handle_s0007 status_code, status_name=nil
      case status_name
      when 'intersection'
        make_status @intersection
      when 'status'
        make_status @dark_mode
      end
    end

    def handle_s0008 status_code, status_name=nil
      case status_name
      when 'intersection'
        make_status @intersection
      when 'status'
        make_status @manual_control
      end
    end

    def handle_s0009 status_code, status_name=nil
      case status_name
      when 'intersection'
        make_status @intersection
      when 'status'
        make_status @fixed_time_control
      end
    end

    def handle_s0010 status_code, status_name=nil
      case status_name
      when 'intersection'
        make_status @intersection
      when 'status'
        make_status @isolated_control
      end
    end

    def handle_s0011 status_code, status_name=nil
      case status_name
      when 'intersection'
        make_status @intersection
      when 'status'
        make_status @yellow_flash
      end
    end

    def handle_s0012 status_code, status_name=nil
      case status_name
      when 'intersection'
        make_status @intersection
      when 'status'
        make_status @all_red
      end
    end

    def handle_s0013 status_code, status_name=nil
      case status_name
      when 'intersection'
        make_status @intersection
      when 'status'
        make_status @police_key
      end
    end

    def handle_s0014 status_code, status_name=nil
      case status_name
      when 'status'
        make_status @plan
      end
    end

    def handle_s0015 status_code, status_name=nil
      case status_name
      when 'status'
        make_status @traffic_situation
      end
    end

    def handle_s0016 status_code, status_name=nil
      case status_name
      when 'number'
        make_status @detector_logics.size
      end
    end

    def handle_s0017 status_code, status_name=nil
      case status_name
      when 'number'
        make_status @signal_groups.size
      end
    end

    def handle_s0018 status_code, status_name=nil
      case status_name
      when 'number'
        make_status @plans.size
      end
    end

    def handle_s0019 status_code, status_name=nil
      case status_name
      when 'number'
        make_status @num_traffic_situations
      end
    end

    def handle_s0020 status_code, status_name=nil
      case status_name
      when 'intersection'
        make_status @intersection
      when 'controlmode'
        make_status @control_mode
      end
    end

    def handle_s0021 status_code, status_name=nil
      case status_name
      when 'detectorlogics'
        make_status @detector_logics.map { |logic| logic.manual.to_s }.join
      end
    end

    def handle_s0022 status_code, status_name=nil
      case status_name
      when 'status'
        make_status '1'
      end
    end

    def handle_s0023 status_code, status_name=nil
      case status_name
      when 'status'
        make_status '1-1-0'
      end
    end

    def handle_s0024 status_code, status_name=nil
      case status_name
      when 'status'
        make_status '1-0'
      end
    end

    def handle_s0025 status_code, status_name=nil
      case status_name
      when 'minToGEstimate'
        make_status RSMP.now_string
      when 'maxToGEstimate'
        make_status RSMP.now_string
      when 'likelyToGEstimate'
        make_status RSMP.now_string
      when 'ToGConfidence'
        make_status 0
      when 'minToREstimate'
        make_status RSMP.now_string
      when 'maxToREstimate'
        make_status RSMP.now_string
      when 'likelyToREstimate'
        make_status RSMP.now_string
      when 'ToRConfidence'
        make_status 0
      end
    end

    def handle_s0026 status_code, status_name=nil
      case status_name
      when 'status'
        make_status '0-00'
      end
    end

    def handle_s0027 status_code, status_name=nil
      case status_name
      when 'status'
        make_status '00-00-00-00'
      end
    end

    def handle_s0028 status_code, status_name=nil
      case status_name
      when 'status'
        make_status '00-00'
      end
    end

    def handle_s0029 status_code, status_name=nil
      case status_name
      when 'status'
        make_status ''
      end
    end

    def handle_s0091 status_code, status_name=nil
      case status_name
      when 'user'
        make_status 'nobody'
      when 'status'
        make_status 'logout'
      end
    end

    def handle_s0092 status_code, status_name=nil
      case status_name
      when 'user'
        make_status 'nobody'
      when 'status'
        make_status 'logout'
      end
    end

    def handle_s0095 status_code, status_name=nil
      case status_name
      when 'status'
        make_status RSMP::VERSION
      end
    end

    def handle_s0096 status_code, status_name=nil
      case status_name
      when 'year'
        make_status RSMP.now_object.year.to_s.rjust(4, "0")
      when 'month'
        make_status RSMP.now_object.month.to_s.rjust(2, "0")
      when 'day'
        make_status RSMP.now_object.day.to_s.rjust(2, "0")
      when 'hour'
        make_status RSMP.now_object.hour.to_s.rjust(2, "0")
      when 'minute'
        make_status RSMP.now_object.min.to_s.rjust(2, "0")
      when 'second'
        make_status RSMP.now_object.sec.to_s.rjust(2, "0")
      end
    end

    def handle_s0201 status_code, status_name=nil
      case status_name
      when 'starttime'
        make_status RSMP.now_string
      when 'vehicles'
        make_status 0
      end
    end

    def handle_s0202 status_code, status_name=nil
      case status_name
      when 'starttime'
        make_status RSMP.now_string
      when 'speed'
        make_status 0
      end
    end

    def handle_s0203 status_code, status_name=nil
      case status_name
      when 'starttime'
        make_status RSMP.now_string
      when 'occupancy'
        make_status 0
      end
    end

    def handle_s0204 status_code, status_name=nil
      case status_name
      when 'starttime'
        make_status RSMP.now_string
      when 'P'
        make_status 0
      when 'PS'
        make_status 0
      when 'L'
        make_status 0
      when 'LS'
        make_status 0
      when 'B'
        make_status 0
      when 'SP'
        make_status 0
      when 'MC'
        make_status 0
      when 'C'
        make_status 0
      when 'F'
        make_status 0
      end
    end

    def handle_s0205 status_code, status_name=nil
      case status_name
      when 'start'
        make_status RSMP.now_string
      when 'vehicles'
        make_status 0
      end
    end

    def handle_s0206 status_code, status_name=nil
      case status_name
      when 'start'
        make_status RSMP.now_string
      when 'speed'
        make_status 0
      end
    end

    def handle_s0207 status_code, status_name=nil
      case status_name
      when 'start'
        make_status RSMP.now_string
      when 'occupancy'
        make_status 0
      end
    end

    def handle_s0208 status_code, status_name=nil
      case status_name
      when 'start'
        make_status RSMP.now_string
      when 'P'
        make_status 0
      when 'PS'
        make_status 0
      when 'L'
        make_status 0
      when 'LS'
        make_status 0
      when 'B'
        make_status 0
      when 'SP'
        make_status 0
      when 'MC'
        make_status 0
      when 'C'
        make_status 0
      when 'F'
        make_status 0
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

  class DetectorLogic < Component
    attr_reader :state, :manual

    def initialize node:, id:
      super node: node, id: id, grouped: false
      @state = 0
      @manual = 0
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

    def build_component id:, type:, settings:{}
      component = case type
      when 'main'
        @main = TrafficController.new node: self, id: id, cycle_time: settings['cycle_time']
      when 'signal_group'
        group = SignalGroup.new node: self, id: id, plan: settings['plan']
        @main.add_signal_group group
        group
      when 'detector_logic'
        logic = DetectorLogic.new node: self, id: id
        @main.add_detector_logic logic
        logic
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