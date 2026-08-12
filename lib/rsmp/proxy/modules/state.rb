module RSMP
  class Proxy
    module Modules
      # State management helpers
      # Utility methods for waiting on state changes
      module State
        def secure_peer_credential_id
          @protocol&.authenticated_peer_id if @protocol.respond_to?(:authenticated_peer_id)
        end

        def secure_runtime_settings(settings)
          RSMP::Secure.with_runtime_policy(settings, revocation_list: @node.secure_revocation_list)
        end

        def ready?
          @state == :ready
        end

        def connected?
          @state == :connected || @state == :ready
        end

        def disconnected?
          @state == :disconnected
        end

        def state=(state)
          return if state == @state

          @state = state
          state_changed
        end

        def state_changed
          @state_condition.signal @state
        end

        def wait_for_state(state, timeout:)
          states = [state].flatten
          return true if states.include?(@state)

          wait_for_condition(@state_condition, timeout: timeout) do
            states.include?(@state)
          end
          true
        rescue RSMP::TimeoutError
          raise RSMP::TimeoutError, "Did not reach state #{state} within #{timeout}s"
        end

        def handshake_complete
          build_sxl_interfaces
          self.state = :ready
        end
      end
    end
  end
end
