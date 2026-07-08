module RSMP
  module Secure
    # Formats Secure RSMP handshake failures for logs and connection errors.
    module ProtocolErrors
      private

      def handshake_error_message(error)
        if defined?(Edhoc::CredentialsError) && error.is_a?(Edhoc::CredentialsError)
          return "EDHOC handshake failed: #{error.message}" if error.message.start_with?('peer credential ')

          return "EDHOC handshake failed: peer credential is not trusted by this #{role} " \
                 "(configured secure peers: #{configured_peer_summary})"
        end

        "EDHOC handshake failed: #{error.message}"
      end

      def configured_peer_summary
        peers = @settings.fetch('peers', [])
        ids = peers.map { |peer| peer['id'] }.compact
        ids.empty? ? 'none' : ids.join(', ')
      end
    end
  end
end
