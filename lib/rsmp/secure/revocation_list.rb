module RSMP
  module Secure
    # Process-local credential revocations shared by current and new sessions.
    class RevocationList
      def initialize
        @credential_ids = Set.new
        @mutex = Mutex.new
      end

      def revoke(credential_id)
        @mutex.synchronize { !!@credential_ids.add?(normalize(credential_id)) }
      end

      def restore(credential_id)
        @mutex.synchronize { !@credential_ids.delete?(normalize(credential_id)).nil? }
      end

      def revoked?(credential_id)
        @mutex.synchronize { @credential_ids.include?(normalize(credential_id)) }
      end

      private

      def normalize(credential_id)
        value = credential_id.to_s.dup.force_encoding(Encoding::UTF_8)
        valid = !value.empty? && value.valid_encoding?
        raise ArgumentError, 'Secure credential id must be a non-empty UTF-8 string' unless valid

        value.freeze
      end
    end
  end
end
