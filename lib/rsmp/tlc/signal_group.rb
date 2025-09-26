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

      DEFAULT_STATE = 'a'.freeze
      FLASH_STATE = 'c'.freeze
      VALID_SIGNAL_STATES = /[a-hA-G0-9N-P]/

      def compute_state
        return DEFAULT_STATE if dark?
        return FLASH_STATE if yellow_flash?
        return startup_state if startup_sequence_active?

        determined_state || DEFAULT_STATE
      end

      private

      def dark?
        node.main.dark?
      end

      def yellow_flash?
        node.main.yellow_flash?
      end

      def startup_sequence_active?
        node.main.startup_sequence_active
      end

      def startup_state
        node.main.startup_state || DEFAULT_STATE
      end

      def determined_state
        states = active_plan_states
        return unless states

        state = states[state_index(states)]
        valid_signal_state?(state) ? state : nil
      end

      def active_plan_states
        plan = node.main.current_plan
        return unless plan&.states

        plan.states[c_id]
      end

      def state_index(states)
        [node.main.cycle_counter, states.length - 1].min
      end

      def valid_signal_state?(state)
        state =~ VALID_SIGNAL_STATES
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
