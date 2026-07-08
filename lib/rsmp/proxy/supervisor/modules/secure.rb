module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Secure RSMP helpers for supervisor-side connections.
      module Secure
        def secure_settings
          RSMP::Secure.site_peer_settings(@site_settings, @supervisor_settings)
        end

        def check_secure_supervisor_id(message)
          expected = @supervisor_settings.dig('secure', 'supervisor_id')
          return unless expected

          actual = message.attributes['supervisorId']
          return if actual == expected

          raise HandshakeError, "Secure supervisor credential is not authorized for supervisor #{actual.inspect}"
        end
      end
    end
  end
end
