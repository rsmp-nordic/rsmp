# frozen_string_literal: true

module RSMP
  class Proxy
    module Modules
      # State management for proxy connections
      # Handles state transitions and notifications
      module StateManagement
        def ready?
          @state == :ready
        end

        # change our state
        def state=(state)
          return if state == @state

          @state = state
          state_changed
        end

        # the state changed
        # override to to things like notifications
        def state_changed
          @state_condition.signal @state
        end

        def wait_for_state(state, timeout:)
          states = [state].flatten
          return if states.include?(@state)

          wait_for_condition(@state_condition, timeout: timeout) do
            states.include?(@state)
          end
          @state
        rescue RSMP::TimeoutError
          raise RSMP::TimeoutError, "Did not reach state #{state} within #{timeout}s"
        end

        def clear
          @awaiting_acknowledgement = {}
          @latest_watchdog_received = nil
          @watchdog_started = false
          @version_determined = false
          @ingoing_acknowledged = {}
          @outgoing_acknowledged = {}
          @latest_watchdog_send_at = nil

          @acknowledgements = {}
          @acknowledgement_condition = Async::Notification.new
        end

        def handshake_complete
          self.state = :ready
        end
      end
    end
  end
end
