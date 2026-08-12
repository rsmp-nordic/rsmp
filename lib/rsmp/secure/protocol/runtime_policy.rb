module RSMP
  module Secure
    class Protocol
      # Applies process-local revocation and failed-connection controls.
      module RuntimePolicy
        private

        def validate_peer_not_revoked!
          revocations = @settings[REVOCATION_LIST_KEY]
          return unless revocations&.revoked?(@authenticated_peer_id)

          raise AuthenticationError, 'Authenticated secure credential has been revoked'
        end

        def record_failed_connection(error)
          return unless error.is_a?(Error) || error.is_a?(HandshakeError)
          return if @connection_failure_recorded

          limiter = @settings[RATE_LIMITER_KEY]
          return unless limiter

          limiter.record_failure(@settings[RATE_LIMIT_KEY])
          @connection_failure_recorded = true
        end
      end
    end
  end
end
