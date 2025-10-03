module RSMP
  module TLC
    # TrafficController is the main component of a TrafficControllerSite.
    # It handles all command and status for the main component,
    # and keeps track of signal plans, detector logics, inputs, etc. which do
    # not have dedicated components.
    class TrafficController < Component
      include TLC::Modules::System
      include TLC::Modules::Modes
      include TLC::Modules::Plans
      include TLC::Modules::SignalGroups
      include TLC::Modules::Inputs
      include TLC::Modules::Outputs
      include TLC::Modules::DetectorLogics
      include TLC::Modules::TrafficData
      include TLC::Modules::State
      include TLC::Modules::StartupSequence
      include TLC::Modules::Display
      include TLC::Modules::Helpers

      attr_reader :pos, :cycle_time, :plan, :cycle_counter,
                  :functional_position,
                  :startup_sequence_active, :startup_sequence, :startup_sequence_pos

      def initialize(node:, id:, ntsoid: nil, xnid: nil, **options)
        super(node: node, id: id, ntsoid: ntsoid, xnid: xnid, grouped: true)
        @signal_groups = []
        @detector_logics = []
        @plans = options[:signal_plans]
        @num_traffic_situations = 1
        setup_inputs(options[:inputs])
        @startup_sequence = options[:startup_sequence]
        @live_output = options[:live_output]
        reset
      end

      def setup_inputs(inputs)
        if inputs
          num_inputs = inputs['total']
          @input_programming = inputs['programming']
        else
          @input_programming = nil
        end
        @inputs = TLC::InputStates.new num_inputs || 8
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
    end
  end
end
