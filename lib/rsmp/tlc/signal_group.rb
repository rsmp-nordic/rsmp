module RSMP
  module TLC
    class SignalGroup < Component
      attr_reader :plan, :state

      # plan is a string, with each character representing a signal phase at a particular second in the cycle
      def initialize(node:, id:)
        super(node: node, id: id, grouped: false)
      end

      def timer
        @state = compute_state
      end

      def compute_state
        return 'a' if node.main.dark?
        return 'c' if node.main.yellow_flash?
        return startup_state if node.main.startup_sequence.active?

        compute_plan_state
      end

      def startup_state
        node.main.startup_state || 'a'
      end

      def compute_plan_state
        default = 'a' # phase a means disabled/dark
        plan = node.main.current_plan
        return default unless plan&.states

        states = plan.states[c_id]
        return default unless states

        state_at_cycle_position(states, node.main.cycle_counter, default)
      end

      def state_at_cycle_position(states, cycle_counter, default)
        counter = [cycle_counter, states.length - 1].min
        state = states[counter]
        return default unless state =~ /[a-hA-G0-9N-P]/ # valid signal group states

        state
      end

      def handle_command(command_code, arg, options = {})
        case command_code
        when 'M0010', 'M0011'
          send("handle_#{command_code.downcase}", arg, options)
        else
          raise UnknownCommand, "Unknown command #{command_code}"
        end
      end

      # Start of signal group. Orders a signal group to green
      def handle_m0010(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
        return unless TrafficControllerSite.from_rsmp_bool? arg['status']

        log "Start signal group #{c_id}, go to green", level: :info
      end

      # Stop of signal group. Orders a signal group to red
      def handle_m0011(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
        return unless TrafficControllerSite.from_rsmp_bool? arg['status']

        log "Stop signal group #{c_id}, go to red", level: :info
      end

      def get_status(code, name = nil, _options = {})
        case code
        when 'S0025'
          send("handle_#{code.downcase}", code, name)
        else
          raise InvalidMessage, "unknown status code #{code}"
        end
      end

      def handle_s0025(_status_code, status_name = nil, _options = {})
        now = @node.clock.to_s
        case status_name
        when 'minToGEstimate', 'maxToGEstimate', 'likelyToGEstimate',
             'minToREstimate', 'maxToREstimate', 'likelyToREstimate'
          TrafficControllerSite.make_status now
        when 'ToGConfidence', 'ToRConfidence'
          TrafficControllerSite.make_status 0
        end
      end
    end
  end
end
