module RSMP
  module Secure
    # Secure RSMP v1 forbids every critical and non-critical EDHOC EAD item.
    class RejectEad
      def compose(_context)
        []
      end

      def supports?(_label)
        false
      end

      def process(_context, tokens)
        return if tokens.empty?

        raise Edhoc::EadError, 'Secure RSMP v1 does not permit EDHOC EAD'
      end
    end
  end
end
