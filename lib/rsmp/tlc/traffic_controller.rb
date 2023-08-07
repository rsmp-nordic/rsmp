module RSMP
  module TLC
    # TrafficController is the main component of a TrafficControllerSite.
    # It handles all command and status for the main component,
    # and keeps track of signal plans, detector logics, inputs, etc. which do
    # not have dedicated components.
    class TrafficController < Component
      attr_reader :pos, :cycle_time, :plan, :cycle_counter,
        :functional_position,
        :startup_sequence_active, :startup_sequence, :startup_sequence_pos

      def initialize node:, id:, ntsOId: nil, xNId: nil, cycle_time: 10, signal_plans:,
          startup_sequence:, live_output:nil, inputs:{}
        super node: node, id: id, ntsOId: ntsOId, xNId: xNId, grouped: true
        @signal_groups = []
        @detector_logics = []
        @plans = signal_plans
        @cycle_time = cycle_time
        @num_traffic_situations = 1

        if inputs
          num_inputs = inputs['total']
          @input_programming = inputs['programming']
        else
          @input_programming = nil
        end
        @inputs = TLC::Inputs.new num_inputs || 8

        @startup_sequence = startup_sequence
        @live_output = live_output
        reset
      end

      def reset_modes
        @function_position = 'NormalControl'
        @function_position_source = 'startup'
        @previous_functional_position = nil
        @functional_position_timeout = nil

        @booting = false
        @is_starting = false
        @control_mode = 'control'
        @manual_control = false
        @manual_control_source = 'startup'
        @fixed_time_control = false
        @fixed_time_control_source = 'startup'
        @isolated_control = false
        @isolated_control_source = 'startup'
        @all_red = false
        @all_red_source = 'startup'
        @police_key = 0
      end

      def reset
        reset_modes
        @cycle_counter = 0
        @plan = 1
        @plan_source = 'startup'
        @intersection = 0
        @intersection_source = 'startup'
        @emergency_route = false
        @emergency_route_number = 0
        @traffic_situation = 0
        @traffic_situation_source = 'startup'
        @day_time_table = {}
        @startup_sequence_active = false
        @startup_sequence_initiated_at = nil
        @startup_sequence_pos = 0
        @time_int = nil
        @inputs.reset
        @signal_priorities = []
        @dynamic_bands_timeout = 0
      end

      def dark?
        @function_position == 'Dark'
      end

      def yellow_flash?
        @function_position == 'YellowFlash'
      end

      def normal_control?
        @function_position == 'NormalControl'
      end

      def clock
        node.clock
      end

      def current_plan
        # TODO plan 0 should means use time table
        if @plans
          @plans[ plan ] || @plans.values.first
        else
          nil
        end
      end

      def add_signal_group group
        @signal_groups << group
      end

      def add_detector_logic logic
        @detector_logics << logic
      end

      def timer now
        # TODO use monotone timer, to avoid jumps in case the user sets the system time
        time = Time.now.to_i
        return if time == @time_int
        @time_int = time
        move_cycle_counter
        check_functional_position_timeout
        move_startup_sequence if @startup_sequence_active

        @signal_groups.each { |group| group.timer }
        @signal_priorities.each {|priority| priority.timer }

        output_states
        prune_priorities
      end

      def signal_priority_changed priority, state
        #puts "priority #{priority.id} -> #{state}"
      end

      def prune_priorities
        # TODO spec states that update must be send one time when it reaches the state 'completed',
        # and then be removed. so we need to know when it has been sent
        @signal_priorities.delete_if {|priority| priority.state=='completed' && priority.age >= 1.5 }
      end

      def get_priority_list
        @signal_priorities.map do |priority|
          {
            "r" => priority.id,
            "t" => RSMP::Clock.to_s(priority.updated),
            "s" => priority.state
          }
        end
      end

      def move_cycle_counter
        counter = Time.now.to_i % @cycle_time
        @cycle_counter = counter
      end

      def check_functional_position_timeout
        return unless @functional_position_timeout
        if clock.now >= @functional_position_timeout
          switch_functional_position @previous_functional_position, reverting: true, source: 'calendar_clock'
          @functional_position_timeout = nil
          @previous_functional_position = nil
        end
      end

      def startup_state
        return unless @startup_sequence_active
        return unless @startup_sequence_pos
        @startup_sequence[ @startup_sequence_pos ]
      end

      def initiate_startup_sequence
        log "Initiating startup sequence", level: :info
        reset_modes
        @startup_sequence_active = true
        @startup_sequence_initiated_at = nil
        @startup_sequence_pos = nil
      end

      def end_startup_sequence
        @startup_sequence_active = false
        @startup_sequence_initiated_at = nil
        @startup_sequence_pos = nil
      end

      def move_startup_sequence
        was = @startup_sequence_pos
        if @startup_sequence_initiated_at == nil
          @startup_sequence_initiated_at = Time.now.to_i + 1
          @startup_sequence_pos = 0
        else
          @startup_sequence_pos = Time.now.to_i - @startup_sequence_initiated_at
        end
        if @startup_sequence_pos >= @startup_sequence.size
          end_startup_sequence
        end
      end

      def output_states
        return unless @live_output

        str = @signal_groups.map do |group|
          state = group.state
          s = "#{group.c_id}:#{state}"
          if state =~ /^[1-9]$/
              s.colorize(:green)
          elsif state =~ /^[NOP]$/
            s.colorize(:yellow)
          elsif state =~ /^[ae]$/
            s.colorize(:light_black)
          elsif state =~ /^[f]$/
            s.colorize(:yellow)
          elsif state =~ /^[g]$/
            s.colorize(:red)
          else
            s.colorize(:red)
          end
        end.join ' '

        modes = '.'*9
        modes[0] = 'N' if @function_position == 'NormalControl'
        modes[1] = 'Y' if @function_position == 'YellowFlash'
        modes[2] = 'D' if @function_position == 'Dark'
        modes[3] = 'B' if @booting
        modes[4] = 'S' if @startup_sequence_active
        modes[5] = 'M' if @manual_control
        modes[6] = 'F' if @fixed_time_control
        modes[7] = 'R' if @all_red
        modes[8] = 'I' if @isolated_control
        modes[9] = 'P' if @police_key != 0

        plan = "P#{@plan}"

        # create folders if needed
        FileUtils.mkdir_p File.dirname(@live_output)

        # append a line with the current state to the file
        File.open @live_output, 'w' do |file|
          file.puts "#{modes}  #{plan.rjust(2)}  #{@cycle_counter.to_s.rjust(3)}  #{str}\r"
        end
      end

      def format_signal_group_status
        @signal_groups.map { |group| group.state }.join
      end

      def handle_command command_code, arg, options={}
        case command_code
        when 'M0001', 'M0002', 'M0003', 'M0004', 'M0005', 'M0006', 'M0007',
             'M0012', 'M0013', 'M0014', 'M0015', 'M0016', 'M0017', 'M0018',
             'M0019', 'M0020', 'M0021', 'M0022', 'M0023',
             'M0103', 'M0104'

          return send("handle_#{command_code.downcase}", arg, options)
        else
          raise UnknownCommand.new "Unknown command #{command_code}"
        end
      end

      def handle_m0001 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        switch_functional_position arg['status'],
          timeout: arg['timeout'].to_i*60,
          source: 'forced'

      end

      def handle_m0002 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        if TrafficControllerSite.from_rsmp_bool(arg['status'])
          switch_plan arg['timeplan'], source: 'force'
        else
          switch_plan 0, source: 'startup'     # TODO use clock/calender
        end
      end

      def handle_m0003 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        switch_traffic_situation arg['traficsituation'], source: 'forced'
      end

      def switch_traffic_situation situation, source:
        @traffic_situation = situation.to_i
        @traffic_situation_source = 'forced'
      end

      def handle_m0004 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        # don't restart immeediately, since we need to first send command response
        # instead, defer an action, which will be handled by the TLC site
        log "Sheduling restart of TLC", level: :info
        @node.defer :restart
      end

      def handle_m0005 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        @emergency_route = (arg['status'] == 'True')
        @emergency_route_number = arg['emergencyroute'].to_i

        if @emergency_route
          log "Switching to emergency route #{@emergency_route_number}", level: :info
        else
          log "Switching off emergency route", level: :info
        end
      end

      def input_logic input, change
        return unless @input_programming && change != nil
        action = @input_programming[input]
        return unless action
        if action['raise_alarm']
          if action['component']
            component = node.find_component action['component']
          else
            component = node.main
          end
          alarm_code = action['raise_alarm']
          if change
            log "Activating input #{input} is programmed to raise alarm #{alarm_code} on #{component.c_id}", level: :info
            component.activate_alarm alarm_code
          else
            log "Deactivating input #{input} is programmed to clear alarm #{alarm_code} on #{component.c_id}", level: :info
            component.deactivate_alarm alarm_code
          end
        end
      end

      def handle_m0006 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        input = arg['input'].to_i
        status = string_to_bool arg['status']
        unless input>=1 && input<=@inputs.size
          raise MessageRejected.new("Input must be in the range 1-#{@inputs.size}")
        end
        if status
          log "Activating input #{input}", level: :info
        else
          log "Deactivating input #{input}", level: :info
        end
        change = @inputs.set input, status
        input_logic input, change if change != nil
      end

      def handle_m0007 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        set_fixed_time_control arg['status'], source: 'forced'
      end

      def handle_m0012 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0013 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        set, clear = [], []
        arg['status'].split(';').map do |part|
          offset, set_bits, clear_bits = part.split(',').map { |i| i.to_i }
          set_bits.to_s(2).reverse.each_char.with_index do |bit,i|
            set << i + offset if bit == '1'
          end
          clear_bits.to_s(2).reverse.each_char.with_index do |bit,i|
            clear << i + offset if bit == '1'
          end
        end

        set = set.uniq.sort
        clear = clear.uniq.sort

        # if input is both activated and deacticvated, there is no need to acticate first
        set -= (set & clear)

        [set,clear].each do |inputs|
          inputs.each do |input|
            if input<1
            raise MessageRejected.new("Cannot acticate inputs #{set} and deactive inputs #{clear}: input #{input} is invalid (must be 1 or higher)"
              ) if input<1
            end
            if input>@inputs.size
              raise MessageRejected.new("Cannot acticate inputs #{set} and deactive inputs #{clear}: input #{input} is invalid (only #{@inputs.size} inputs present)")
            end
          end
        end

        log "Activating inputs #{set} and deactivating inputs #{clear}", level: :info

        set.each do |input|
          change = @inputs.set input, true
          input_logic input, change if change != nil
        end
        clear.each do |input|
          change = @inputs.set input, false
          input_logic input, change if change != nil
        end
      end

      def find_plan plan_nr
        plan = @plans[plan_nr.to_i]
        raise InvalidMessage.new "unknown signal plan #{plan_nr}, known only [#{@plans.keys.join(',')}]" unless plan
        plan
      end

      def handle_m0014 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        plan = find_plan arg['plan']
        arg['status'].split(',').each do |item|
          matched = /(\d+)-(\d+)/.match item
          band = matched[1].to_i
          value = matched[2].to_i
          log "Set plan #{arg['plan']} dynamic band #{band} to #{value}", level: :info
          plan.set_band band, value
        end
      end

      def handle_m0015 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0016 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0017 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        arg['status'].split(',').each do |item|
          elems = item.split('-')
          nr = elems[0].to_i
          plan = elems[1].to_i
          hour = elems[2].to_i
          min = elems[3].to_i
          if nr<0 || nr>12
            raise InvalidMessage.new "time table id must be between 0 and 12, got #{nr}"
          end
          #p "nr: #{nr}, plan #{plan} at #{hour}:#{min}"
          @day_time_table[nr] = {plan: plan, hour: hour, min:min}
        end
      end

      def handle_m0018 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
      end

      def string_to_bool bool_str
        case bool_str
          when 'True'
            true
          when 'False'
            false
          else
            raise RSMP::MessageRejected.new "Invalid boolean '#{bool}', must be 'True' or 'False'"
        end
      end

      def bool_string_to_digit bool
        case bool
          when 'True'
            '1'
          when 'False'
            '0'
          else
            raise RSMP::MessageRejected.new "Invalid boolean '#{bool}', must be 'True' or 'False'"
        end
      end

      def bool_to_digit bool
        bool ?  '1' : '0'
      end

      def handle_m0019 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        input = arg['input'].to_i
        force = string_to_bool arg['status']
        forced_value = string_to_bool arg['inputValue']
        unless input>=1 && input<=@inputs.size
          raise MessageRejected.new("Input must be in the range 1-#{@inputs.size}")
        end
        if force
          log "Forcing input #{input} to #{forced_value}", level: :info
        else
          log "Releasing input #{input}", level: :info
        end
        change = @inputs.set_forcing input, force, forced_value

        input_logic input, change if change != nil
      end

      def handle_m0020 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0021 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0022 arg, options={}
        id = arg['requestId']
        type = arg['type']
        priority = @signal_priorities.find { |priority| priority.id == id }
        case type
        when 'new'
          if priority
            raise MessageRejected.new("Priority Request #{id} already exists")
          else
            #ref = arg.slice('signalGroupId','inputId','connectionId','approachId','laneInId','laneOutId')
            if arg['signalGroupId']
              signal_group = node.find_component arg['signalGroupId']
            end

            level = arg['level']
            eta = arg['eta']
            vehicleType = arg['vehicleType']
            @signal_priorities << SignalPriority.new(node:self, id:id, level:level, eta:eta, vehicleType:vehicleType)
            log "Priority request for signal group #{signal_group.c_id} received with id #{id}", level: :info
          end          
        when 'update'
          if priority
            log "Priority Request #{id} updated", level: :info
          else
            raise MessageRejected.new("Cannot update priority request #{id}, not found")
          end
        when 'cancel'
          if priority
            @signal_priorities.delete priority
          else
            raise MessageRejected.new("Cannot cancel priority request #{id}, not found")
          end    
        else
          raise MessageRejected.new("Unknown type #{type}")
        end
      end

      def handle_m0023 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        timeout = arg['status'].to_i
        unless timeout>=0 and timeout <= 65535
          raise RSMP::MessageRejected.new "Timeout must be in the range 0-65535, got #{timeout}"
        end
        if timeout == 0
          log "Dynamic bands timeout disabled", level: :info
        else
          log "Dynamic bands timeout set to #{timeout}min", level: :info
        end
        @dynamic_bands_timeout = timeout
      end

      def handle_m0103 arg, options={}
        level = {'Level1'=>1,'Level2'=>2}[arg['status']]
        @node.change_security_code level, arg['oldSecurityCode'], arg['newSecurityCode']
      end

      def handle_m0104 arg, options={}
        @node.verify_security_code 1, arg['securityCode']
        time = Time.new(
          arg['year'],
          arg['month'],
          arg['day'],
          arg['hour'],
          arg['minute'],
          arg['second'],
          'UTC'
        )
        clock.set time
        log "Clock set to #{time}, (adjustment is #{clock.adjustment}s)", level: :info
      end

      def set_input i, value
        return unless i>=0 && i<@num_inputs
        @inputs[i] = bool_to_digit arg['value']
      end

      def set_fixed_time_control status, source:
        @fixed_time_control = status
        @fixed_time_control_source = source
      end

      def switch_plan plan, source:
        plan_nr = plan.to_i
        if plan_nr == 0
          log "Switching to plan selection by time table", level: :info
        else
          plan = find_plan plan_nr
          log "Switching to plan #{plan_nr}", level: :info
        end
        @plan = plan_nr
        @plan_source = source
      end

      def switch_functional_position mode, timeout: nil, reverting: false, source:
        unless ['NormalControl','YellowFlash','Dark'].include? mode
          raise RSMP::MessageRejected.new "Invalid functional position #{mode.inspect}, must be NormalControl, YellowFlash or Dark"
        end
        if reverting
          log "Reverting to functional position #{mode} after timeout", level: :info
        elsif timeout && timeout > 0
          log "Switching to functional position #{mode} with timeout #{(timeout/60).round(1)}min", level: :info
          @previous_functional_position = @function_position
          now = clock.now
          @functional_position_timeout = now + timeout
        else
          log "Switching to functional position #{mode}", level: :info
        end 
        if mode == 'NormalControl'
          initiate_startup_sequence if @function_position != 'NormalControl'
        end
        @function_position = mode
        @function_position_source = source
        mode
      end

      def get_status code, name=nil, options={}
        case code
        when 'S0001', 'S0002', 'S0003', 'S0004', 'S0005', 'S0006', 'S0007',
             'S0008', 'S0009', 'S0010', 'S0011', 'S0012', 'S0013', 'S0014',
             'S0015', 'S0016', 'S0017', 'S0018', 'S0019', 'S0020', 'S0021',
             'S0022', 'S0023', 'S0024', 'S0026', 'S0027', 'S0028',
             'S0029', 'S0030', 'S0031', 'S0032', 'S0033',
             'S0091', 'S0092', 'S0095', 'S0096', 'S0097',
             'S0205', 'S0206', 'S0207', 'S0208'
          return send("handle_#{code.downcase}", code, name, options)
        else
          raise InvalidMessage.new "unknown status code #{code}"
        end
      end

      def handle_s0001 status_code, status_name=nil, options={}
        case status_name
        when 'signalgroupstatus'
          TrafficControllerSite.make_status format_signal_group_status
        when 'cyclecounter'
          TrafficControllerSite.make_status @cycle_counter.to_s
        when 'basecyclecounter'
          TrafficControllerSite.make_status @cycle_counter.to_s
        when 'stage'
          TrafficControllerSite.make_status 0.to_s
        end
      end

      def handle_s0002 status_code, status_name=nil, options={}
        case status_name
        when 'detectorlogicstatus'
          TrafficControllerSite.make_status @detector_logics.map { |dl| bool_to_digit(dl.value) }.join
        end
      end

      def handle_s0003 status_code, status_name=nil, options={}
        case status_name
        when 'inputstatus'
          TrafficControllerSite.make_status @inputs.actual_string
        when 'extendedinputstatus'
          TrafficControllerSite.make_status 0.to_s
        end
      end

      def handle_s0004 status_code, status_name=nil, options={}
        case status_name
        when 'outputstatus'
          TrafficControllerSite.make_status 0
        when 'extendedoutputstatus'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0005 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status @is_starting
        end
      end

      def handle_s0006 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status @emergency_route
        when 'emergencystage'
          TrafficControllerSite.make_status @emergency_route_number
        end
      end

      def handle_s0007 status_code, status_name=nil, options={}
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @function_position != 'Dark'
        when 'source'
          TrafficControllerSite.make_status @function_position_source
        end
      end

      def handle_s0008 status_code, status_name=nil, options={}
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @manual_control
        when 'source'
          TrafficControllerSite.make_status @manual_control_source
        end
      end

      def handle_s0009 status_code, status_name=nil, options={}
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @fixed_time_control
        when 'source'
          TrafficControllerSite.make_status @fixed_time_control_source
        end
      end

      def handle_s0010 status_code, status_name=nil, options={}
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @isolated_control
        when 'source'
          TrafficControllerSite.make_status @isolated_control_source
        end
      end

      def handle_s0011 status_code, status_name=nil, options={}
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status TrafficControllerSite.to_rmsp_bool( @function_position == 'YellowFlash' )
        when 'source'
          TrafficControllerSite.make_status @function_position_source
        end
      end

      def handle_s0012 status_code, status_name=nil, options={}
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @all_red
        when 'source'
          TrafficControllerSite.make_status @all_red_source
        end
      end

      def handle_s0013 status_code, status_name=nil, options={}
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @police_key
        end
      end

      def handle_s0014 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status @plan
        when 'source'
          TrafficControllerSite.make_status @plan_source
        end
      end

      def handle_s0015 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status @traffic_situation
        when 'source'
          TrafficControllerSite.make_status @traffic_situation_source
        end
      end

      def handle_s0016 status_code, status_name=nil, options={}
        case status_name
        when 'number'
          TrafficControllerSite.make_status @detector_logics.size
        end
      end

      def handle_s0017 status_code, status_name=nil, options={}
        case status_name
        when 'number'
          TrafficControllerSite.make_status @signal_groups.size
        end
      end

      def handle_s0018 status_code, status_name=nil, options={}
        case status_name
        when 'number'
          TrafficControllerSite.make_status @plans.size
        end
      end

      def handle_s0019 status_code, status_name=nil, options={}
        case status_name
        when 'number'
          TrafficControllerSite.make_status @num_traffic_situations
        end
      end

      def handle_s0020 status_code, status_name=nil, options={}
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'controlmode'
          TrafficControllerSite.make_status @control_mode
        end
      end

      def handle_s0021 status_code, status_name=nil, options={}
        case status_name
        when 'detectorlogics'
          TrafficControllerSite.make_status @detector_logics.map { |logic| bool_to_digit(logic.forced)}.join
        end
      end

      def handle_s0022 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status @plans.keys.join(',')
        end
      end

      def handle_s0023 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          dynamic_bands = @plans.map { |nr,plan| plan.dynamic_bands_string }
          str = dynamic_bands.compact.join(',')
          TrafficControllerSite.make_status str
        end
      end

      def handle_s0024 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status '1-0'
        end
      end

      def handle_s0026 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status '0-00'
        end
      end

      def handle_s0027 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          status = @day_time_table.map do |i,item|
            "#{i}-#{item[:plan]}-#{item[:hour]}-#{item[:min]}"
          end.join(',')
          TrafficControllerSite.make_status status
        end
      end

      def handle_s0028 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status '00-00'
        end
      end

      def handle_s0029 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status @inputs.forced_string
        end
      end

      def handle_s0030 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status ''
        end
      end

      def handle_s0031 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status ''
        end
      end

      def handle_s0032 status_code, status_name=nil, options={}
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status 'local'
        when 'source'
          TrafficControllerSite.make_status @intersection_source
        end
      end

      def handle_s0033 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status get_priority_list
        end
      end

      def handle_s0091 status_code, status_name=nil, options={}
        if Proxy.version_meets_requirement? options[:sxl_version], '>=1.1'
          case status_name
          when 'user'
            TrafficControllerSite.make_status 0
          end
        else
          case status_name
          when 'user'
            TrafficControllerSite.make_status 'nobody'
          when 'status'
            TrafficControllerSite.make_status 'logout'
          end
        end
      end

      def handle_s0092 status_code, status_name=nil, options={}
        if Proxy.version_meets_requirement? options[:sxl_version], '>=1.1'
          case status_name
          when 'user'
            TrafficControllerSite.make_status 0
          end
        else
          case status_name
          when 'user'
            TrafficControllerSite.make_status 'nobody'
          when 'status'
            TrafficControllerSite.make_status 'logout'
          end
        end
      end

      def handle_s0095 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          TrafficControllerSite.make_status RSMP::VERSION
        end
      end

      def handle_s0096 status_code, status_name=nil, options={}
        now = clock.now
        case status_name
        when 'year'
          TrafficControllerSite.make_status now.year.to_s.rjust(4, "0")
        when 'month'
          TrafficControllerSite.make_status now.month.to_s.rjust(2, "0")
        when 'day'
          TrafficControllerSite.make_status now.day.to_s.rjust(2, "0")
        when 'hour'
          TrafficControllerSite.make_status now.hour.to_s.rjust(2, "0")
        when 'minute'
          TrafficControllerSite.make_status now.min.to_s.rjust(2, "0")
        when 'second'
          TrafficControllerSite.make_status now.sec.to_s.rjust(2, "0")
        end
      end

      def handle_s0097 status_code, status_name=nil, options={}
        case status_name
        when 'checksum'
          TrafficControllerSite.make_status '1'
        when 'timestamp'
          now = clock.to_s
          TrafficControllerSite.make_status now
        end
      end

      def handle_s0205 status_code, status_name=nil, options={}
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'vehicles'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0206 status_code, status_name=nil, options={}
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'speed'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0207 status_code, status_name=nil, options={}
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'occupancy'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0208 status_code, status_name=nil, options={}
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'P'
          TrafficControllerSite.make_status 0
        when 'PS'
          TrafficControllerSite.make_status 0
        when 'L'
          TrafficControllerSite.make_status 0
        when 'LS'
          TrafficControllerSite.make_status 0
        when 'B'
          TrafficControllerSite.make_status 0
        when 'SP'
          TrafficControllerSite.make_status 0
        when 'MC'
          TrafficControllerSite.make_status 0
        when 'C'
          TrafficControllerSite.make_status 0
        when 'F'
          TrafficControllerSite.make_status 0
        end
      end
    end
  end
end