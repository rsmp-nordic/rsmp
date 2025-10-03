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

      def timer(_now)
        # TODO: use monotone timer, to avoid jumps in case the user sets the system time
        return unless move_cycle_counter

        check_functional_position_timeout
        move_startup_sequence if @startup_sequence_active

        @signal_groups.each(&:timer)
        @signal_priorities.each(&:timer)

        output_states
      end

      # this method is called by the supervisor proxy each time status updates have been send
      # we can then prune our priority request list
      def status_updates_sent
        prune_priorities
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
