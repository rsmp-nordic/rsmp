module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Secure RSMP helpers for supervisor-side connections.
      module Secure
        def secure_settings
          RSMP::Secure.site_peer_settings(@site_settings, @supervisor_settings)
        end

        def authorize_secure_supervisor(message)
          expected = @supervisor_settings.dig('secure', 'supervisor_id')
          actual = message.attributes['supervisorId'] || expected
          if expected && actual != expected
            raise HandshakeError, "Secure supervisor credential is not authorized for supervisor #{actual.inspect}"
          end
          return unless @protocol.respond_to?(:authorize!)

          actual ||= @protocol.authenticated_peer_id
          @protocol.authorize!(rsmp_id: actual, core_version: @core_version)
        end
      end
    end
  end
end
