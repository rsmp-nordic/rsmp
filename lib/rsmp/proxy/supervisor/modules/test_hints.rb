module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Sends optional Test Hub scenario requests from a simulated site.
      module TestHints
        # Send a scenario request without rejecting any received message.
        # MessageNotAck is intentionally not itself acknowledged or buffered.
        def send_test_hint(scenario)
          unless ready?
            return Result.failure(:not_ready, message: 'Cannot send test hint before handshake completes',
                                              source: :local)
          end

          send_message(TestHint.build(scenario), buffer: false).map(&:message)
        end

        def send_test_hint!(...)
          send_test_hint(...).value!
        end
      end
    end
  end
end
