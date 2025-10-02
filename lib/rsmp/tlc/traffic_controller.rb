module RSMP
  module TLC
    # TrafficController is the main component of a TrafficControllerSite.
    # It handles all command and status for the main component,
    # and keeps track of signal plans, detector logics, inputs, etc. which do
    # not have dedicated components.
    class TrafficController < Component
      include TLC::Modules::System
      include TLC::Modules::Inputs
      include TLC::Modules::Modes

      attr_reader :pos, :cycle_time, :plan, :cycle_counter,
                  :functional_position,
                  :startup_sequence_active, :startup_sequence, :startup_sequence_pos

      def initialize(node:, id:, signal_plans:, startup_sequence:, ntsoid: nil, xnid: nil, live_output: nil, inputs: {})
        super(node: node, id: id, ntsoid: ntsoid, xnid: xnid, grouped: true)
        @signal_groups = []
        @detector_logics = []
        @plans = signal_plans
        @num_traffic_situations = 1

        if inputs
          num_inputs = inputs['total']
          @input_programming = inputs['programming']
        else
          @input_programming = nil
        end
        @inputs = TLC::InputStates.new num_inputs || 8

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
        @emergency_routes = Set.new
        @last_emergency_route = nil
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
        # TODO: plan 0 should means use time table
        return unless @plans

        @plans[plan] || @plans.values.first
      end

      def add_signal_group(group)
        @signal_groups << group
      end

      def add_detector_logic(logic)
        @detector_logics << logic
      end

      def timer(_now)
        # TODO: use monotone timer, to avoid jumps in case the user sets the system time
        return unless move_cycle_counter

        check_functional_position_timeout
        move_startup_sequence if @startup_sequence_active

        @signal_groups.each(&:timer)
        @signal_priorities.each(&:timer)

        output_states
      end

      def signal_priority_changed(priority, state); end

      # remove all stale priority requests
      def prune_priorities
        @signal_priorities.delete_if(&:prune?)
      end

      # this method is called by the supervisor proxy each time status updates have been send
      # we can then prune our priority request list
      def status_updates_sent
        prune_priorities
      end

      def priority_list
        @signal_priorities.map do |priority|
          {
            'r' => priority.id,
            't' => RSMP::Clock.to_s(priority.updated),
            's' => priority.state
          }
        end
      end

      def move_cycle_counter
        plan = current_plan
        counter = if plan
                    Time.now.to_i % plan.cycle_time
                  else
                    0
                  end
        changed = counter != @cycle_counter
        @cycle_counter = counter
        changed
      end

      def check_functional_position_timeout
        return unless @functional_position_timeout

        return unless clock.now >= @functional_position_timeout

        switch_functional_position @previous_functional_position, reverting: true, source: 'calendar_clock'
        @functional_position_timeout = nil
        @previous_functional_position = nil
      end

      def startup_state
        return unless @startup_sequence_active
        return unless @startup_sequence_pos

        @startup_sequence[@startup_sequence_pos]
      end

      def initiate_startup_sequence
        log 'Initiating startup sequence', level: :info
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
        if @startup_sequence_initiated_at.nil?
          @startup_sequence_initiated_at = Time.now.to_i + 1
          @startup_sequence_pos = 0
        else
          @startup_sequence_pos = Time.now.to_i - @startup_sequence_initiated_at
        end
        return unless @startup_sequence_pos >= @startup_sequence.size

        end_startup_sequence
      end

      def output_states
        return unless @live_output

        str = format_colored_signal_states
        modes = format_mode_indicators
        plan = "P#{@plan}"

        write_state_output(modes, plan, str)
      end

      private

      def format_colored_signal_states
        @signal_groups.map do |group|
          state = group.state
          s = "#{group.c_id}:#{state}"
          colorize_signal_state(s, state)
        end.join ' '
      end

      def colorize_signal_state(display_string, state)
        case state
        when /^[1-9]$/
          display_string.colorize(:green)
        when /^[NOPf]$/
          display_string.colorize(:yellow)
        when /^[ae]$/
          display_string.colorize(:light_black)
        else # includes /^g$/ and any other values
          display_string.colorize(:red)
        end
      end

      def format_mode_indicators
        modes = '.' * 9
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
        modes
      end

      def write_state_output(modes, plan, signal_states)
        # create folders if needed
        FileUtils.mkdir_p File.dirname(@live_output)

        # append a line with the current state to the file
        File.open @live_output, 'w' do |file|
          file.puts "#{modes}  #{plan.rjust(2)}  #{@cycle_counter.to_s.rjust(3)}  #{signal_states}\r"
        end
      end

      public

      def format_signal_group_status
        @signal_groups.map(&:state).join
      end

      def handle_command(command_code, arg, options = {})
        case command_code
        when 'M0001', 'M0002', 'M0003', 'M0004', 'M0005', 'M0006', 'M0007',
             'M0012', 'M0013', 'M0014', 'M0015', 'M0016', 'M0017', 'M0018',
             'M0019', 'M0020', 'M0021', 'M0022', 'M0023',
             'M0103', 'M0104'

          send("handle_#{command_code.downcase}", arg, options)
        else
          raise UnknownCommand, "Unknown command #{command_code}"
        end
      end

      def input_logic(input, change)
        return unless @input_programming && !change.nil?

        action = @input_programming[input]
        return unless action

        return unless action['raise_alarm']

        component = if action['component']
                      node.find_component action['component']
                    else
                      node.main
                    end
        alarm_code = action['raise_alarm']
        if change
          log "Activating input #{input} is programmed to raise alarm #{alarm_code} on #{component.c_id}",
              level: :info
          component.activate_alarm alarm_code
        else
          log "Deactivating input #{input} is programmed to clear alarm #{alarm_code} on #{component.c_id}",
              level: :info
          component.deactivate_alarm alarm_code
        end
      end

      def find_plan(plan_nr)
        plan = @plans[plan_nr.to_i]
        raise InvalidMessage, "unknown signal plan #{plan_nr}, known only [#{@plans.keys.join(', ')}]" unless plan

        plan
      end

      def handle_m0014(arg, _options = {})
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

      def handle_m0015(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0016(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0017(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
        arg['status'].split(',').each do |item|
          elems = item.split('-')
          nr = elems[0].to_i
          plan = elems[1].to_i
          hour = elems[2].to_i
          min = elems[3].to_i
          raise InvalidMessage, "time table id must be between 0 and 12, got #{nr}" if nr.negative? || nr > 12

          # p "nr: #{nr}, plan #{plan} at #{hour}:#{min}"
          @day_time_table[nr] = { plan: plan, hour: hour, min: min }
        end
      end

      def handle_m0018(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
        nr = arg['plan'].to_i
        cycle_time = arg['status'].to_i
        plan = @plans[nr]
        raise RSMP::MessageRejected, "Plan '#{nr}' not found" unless plan
        raise RSMP::MessageRejected, 'Cycle time must be greater or equal to zero' if cycle_time.negative?

        log "Set plan #{nr} cycle time to #{cycle_time}", level: :info
        plan.cycle_time = cycle_time
      end

      def string_to_bool(bool_str)
        case bool_str
        when 'True'
          true
        when 'False'
          false
        else
          raise RSMP::MessageRejected, "Invalid boolean '#{bool}', must be 'True' or 'False'"
        end
      end

      def bool_string_to_digit(bool)
        case bool
        when 'True'
          '1'
        when 'False'
          '0'
        else
          raise RSMP::MessageRejected, "Invalid boolean '#{bool}', must be 'True' or 'False'"
        end
      end

      def bool_to_digit(bool)
        bool ? '1' : '0'
      end

      def handle_m0019(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
        input = arg['input'].to_i
        force = string_to_bool arg['status']
        forced_value = string_to_bool arg['inputValue']
        raise MessageRejected, "Input must be in the range 1-#{@inputs.size}" unless input.between?(1, @inputs.size)

        if force
          log "Forcing input #{input} to #{forced_value}", level: :info
        else
          log "Releasing input #{input}", level: :info
        end
        change = @inputs.set_forcing input, force: force, forced_value: forced_value

        input_logic input, change unless change.nil?
      end

      def handle_m0020(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0021(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0022(arg, _options = {})
        id = arg['requestId']
        type = arg['type']
        priority = @signal_priorities.find { |priority| priority.id == id }
        case type
        when 'new'
          raise MessageRejected, "Priority Request #{id} already exists" if priority

          # ref = arg.slice('signalGroupId','inputId','connectionId','approachId','laneInId','laneOutId')
          signal_group = node.find_component arg['signalGroupId'] if arg['signalGroupId']

          level = arg['level']
          eta = arg['eta']
          vehicle_type = arg['vehicleType']
          @signal_priorities << SignalPriority.new(node: self, id: id, level: level, eta: eta,
                                                   vehicle_type: vehicle_type)
          log "Priority request #{id} for signal group #{signal_group.c_id} received.", level: :info

        when 'update'
          raise MessageRejected, "Cannot update priority request #{id}, not found" unless priority

          log "Updating Priority Request #{id}", level: :info

        when 'cancel'
          raise MessageRejected, "Cannot cancel priority request #{id}, not found" unless priority

          priority.cancel
          log "Priority request with id #{id} cancelled.", level: :info

        else
          raise MessageRejected, "Unknown type #{type}"
        end
      end

      def handle_m0023(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
        timeout = arg['status'].to_i
        unless (timeout >= 0) && (timeout <= 65_535)
          raise RSMP::MessageRejected,
                "Timeout must be in the range 0-65535, got #{timeout}"
        end

        if timeout.zero?
          log 'Dynamic bands timeout disabled', level: :info
        else
          log "Dynamic bands timeout set to #{timeout}min", level: :info
        end
        @dynamic_bands_timeout = timeout
      end

      def set_fixed_time_control(status, source:)
        @fixed_time_control = status
        @fixed_time_control_source = source
      end

      def switch_plan(plan, source:)
        plan_nr = plan.to_i
        if plan_nr.zero?
          log 'Switching to plan selection by time table', level: :info
        else
          find_plan plan_nr
          log "Switching to plan #{plan_nr}", level: :info
        end
        @plan = plan_nr
        @plan_source = source
      end

      def switch_functional_position(mode, source:, timeout: nil, reverting: false)
        unless %w[NormalControl YellowFlash Dark].include? mode
          raise RSMP::MessageRejected,
                "Invalid functional position #{mode.inspect}, must be NormalControl, YellowFlash or Dark"
        end

        if reverting
          log "Reverting to functional position #{mode} after timeout", level: :info
        elsif timeout&.positive?
          log "Switching to functional position #{mode} with timeout #{(timeout / 60).round(1)}min", level: :info
          @previous_functional_position = @function_position
          now = clock.now
          @functional_position_timeout = now + timeout
        else
          log "Switching to functional position #{mode}", level: :info
        end
        initiate_startup_sequence if (mode == 'NormalControl') && (@function_position != 'NormalControl')
        @function_position = mode
        @function_position_source = source
        mode
      end

      def get_status(code, name = nil, options = {})
        case code
        when 'S0001', 'S0002', 'S0003', 'S0004', 'S0005', 'S0006', 'S0007',
             'S0008', 'S0009', 'S0010', 'S0011', 'S0012', 'S0013', 'S0014',
             'S0015', 'S0016', 'S0017', 'S0018', 'S0019', 'S0020', 'S0021',
             'S0022', 'S0023', 'S0024', 'S0026', 'S0027', 'S0028',
             'S0029', 'S0030', 'S0031', 'S0032', 'S0033', 'S0035',
             'S0091', 'S0092', 'S0095', 'S0096', 'S0097', 'S0098',
             'S0205', 'S0206', 'S0207', 'S0208'
          send("handle_#{code.downcase}", code, name, options)
        else
          raise InvalidMessage, "unknown status code #{code}"
        end
      end

      def handle_s0008(_status_code, status_name = nil, _options = {})
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @manual_control
        when 'source'
          TrafficControllerSite.make_status @manual_control_source
        end
      end

      def handle_s0009(_status_code, status_name = nil, _options = {})
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @fixed_time_control
        when 'source'
          TrafficControllerSite.make_status @fixed_time_control_source
        end
      end

      def handle_s0010(_status_code, status_name = nil, _options = {})
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @isolated_control
        when 'source'
          TrafficControllerSite.make_status @isolated_control_source
        end
      end

      def handle_s0011(_status_code, status_name = nil, _options = {})
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status TrafficControllerSite.to_rmsp_bool(@function_position == 'YellowFlash')
        when 'source'
          TrafficControllerSite.make_status @function_position_source
        end
      end

      def handle_s0012(_status_code, status_name = nil, _options = {})
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @all_red
        when 'source'
          TrafficControllerSite.make_status @all_red_source
        end
      end

      def handle_s0013(_status_code, status_name = nil, _options = {})
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @police_key
        end
      end

      def handle_s0095(_status_code, status_name = nil, _options = {})
        case status_name
        when 'status'
          TrafficControllerSite.make_status RSMP::VERSION
        end
      end

      def handle_s0096(_status_code, status_name = nil, _options = {})
        now = clock.now
        case status_name
        when 'year'
          TrafficControllerSite.make_status now.year.to_s.rjust(4, '0')
        when 'month'
          TrafficControllerSite.make_status now.month.to_s.rjust(2, '0')
        when 'day'
          TrafficControllerSite.make_status now.day.to_s.rjust(2, '0')
        when 'hour'
          TrafficControllerSite.make_status now.hour.to_s.rjust(2, '0')
        when 'minute'
          TrafficControllerSite.make_status now.min.to_s.rjust(2, '0')
        when 'second'
          TrafficControllerSite.make_status now.sec.to_s.rjust(2, '0')
        end
      end

      def handle_s0097(_status_code, status_name = nil, _options = {})
        case status_name
        when 'checksum'
          TrafficControllerSite.make_status '1'
        when 'timestamp'
          now = clock.to_s
          TrafficControllerSite.make_status now
        end
      end

      def handle_s0098(_status_code, status_name = nil, _options = {})
        settings = node.site_settings.slice('components', 'signal_plans', 'inputs', 'startup_sequence')
        json = JSON.generate(settings)
        case status_name
        when 'config'
          TrafficControllerSite.make_status json
        when 'timestamp'
          now = clock.to_s
          TrafficControllerSite.make_status now
        when 'version'
          TrafficControllerSite.make_status Digest::MD5.hexdigest(json)
        end
      end
    end
  end
end
