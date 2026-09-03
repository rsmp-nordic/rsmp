module RSMP
  class Proxy
    module Modules
      # State management helpers
      # Utility methods for waiting on state changes
      module State
        def wait_for_state(state, timeout:)
          states = [state].flatten
          return Result.success(@state) if states.include?(@state)

          result = wait_for_condition(@state_condition, timeout: timeout) do
            states.include?(@state)
          end
          return Result.success(@state) if result.success?

          Result.failure(
            :timeout,
            message: "Did not reach state #{state} within #{timeout}s",
            source: :timeout,
            context: { expected: states, actual: @state },
            cause: result.failure.cause
          )
        end

        def wait_for_state!(...)
          wait_for_state(...).value!
        end

        def handshake_complete
          build_sxl_interfaces
          self.state = :ready
        end
      end
    end
  end
end
