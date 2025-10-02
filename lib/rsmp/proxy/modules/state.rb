# frozen_string_literal: true

module RSMP
  class Proxy
    module Modules
      # State management helpers
      # Utility methods for waiting on state changes
      module State
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

        def handshake_complete
          self.state = :ready
        end
      end
    end
  end
end
