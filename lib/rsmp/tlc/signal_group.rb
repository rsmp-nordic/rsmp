module RSMP
  module TLC
    class SignalGroup < Component
      attr_reader :plan, :state

      # plan is a string, with each character representing a signal phase at a particular second in the cycle
      def initialize node:, id:
        super node: node, id: id, grouped: false
      end

      def get_state pos
        default = 'a'   # phase a means disabled/dark
        plan = node.main.current_plan
        return default unless plan
        return default unless plan.states
        states = plan.states[c_id]
        return default unless states
        state = states[pos]
        return default unless state =~ /[a-hA-G0-9N-P]/  # valid signal group states
        state
      end

      def move_yellow_flash
        @state = 'c'
      end

      def move_startup pos, sequence
        @state = sequence[pos] || 'a'
      end

      def move_normal pos
        @state = get_state pos
      end

      def handle_command command_code, arg
        case command_code
        when 'M0010', 'M0011'
          return send("handle_#{command_code.downcase}", arg)
        else
          raise UnknownCommand.new "Unknown command #{command_code}"
        end
      end

      # Start of signal group. Orders a signal group to green
      def handle_m0010 arg
        @node.verify_security_code 2, arg['securityCode']
        if TrafficControllerSite.from_rsmp_bool arg['status']
          log "Start signal group #{c_id}, go to green", level: :info
        end
      end

      # Stop of signal group. Orders a signal group to red
      def handle_m0011 arg
        @node.verify_security_code 2, arg['securityCode']
        if TrafficControllerSite.from_rsmp_bool arg['status']
          log "Stop signal group #{c_id}, go to red", level: :info
        end
      end

      def get_status code, name=nil
        case code
        when 'S0025'
          return send("handle_#{code.downcase}", code, name)
        else
          raise InvalidMessage.new "unknown status code #{code}"
        end
      end

      def handle_s0025 status_code, status_name=nil
        now = @node.clock.to_s
        case status_name
        when 'minToGEstimate'
          TrafficControllerSite.make_status now
        when 'maxToGEstimate'
          TrafficControllerSite.make_status now
        when 'likelyToGEstimate'
          TrafficControllerSite.make_status now
        when 'ToGConfidence'
          TrafficControllerSite.make_status 0
        when 'minToREstimate'
          TrafficControllerSite.make_status now
        when 'maxToREstimate'
          TrafficControllerSite.make_status now
        when 'likelyToREstimate'
          TrafficControllerSite.make_status now
        when 'ToRConfidence'
          TrafficControllerSite.make_status 0
        end
      end
    end
  end
end