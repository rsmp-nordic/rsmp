require 'openssl'
require_relative 'cbor'

module RSMP
  module Secure
    # Minimal RFC 9052 COSE_Sign1 profile for Secure RSMP credentials.
    module CoseSign1
      ALGORITHM_LABEL = 1
      EDDSA = -8
      SIGNATURE_BYTES = 64
      KEY_TYPE = 'Ed25519'.freeze
      PROTECTED_HEADERS = Cbor.encode(ALGORITHM_LABEL => EDDSA).freeze
      EXTERNAL_AAD = ''.b.freeze

      module_function

      def sign(payload, private_key:)
        validate_payload(payload)
        signature = signing_key(private_key).sign(nil, sig_structure(payload))
        [PROTECTED_HEADERS, {}, payload, signature]
      end

      def verify(message, public_key:)
        _protected, _unprotected, payload, signature = components(message)
        verifier = OpenSSL::PKey.new_raw_public_key(KEY_TYPE, public_key)
        verifier.verify(nil, signature, sig_structure(payload))
      end

      def payload(message)
        components(message).fetch(2)
      end

      def sig_structure(payload)
        validate_payload(payload)
        Cbor.encode(['Signature1', PROTECTED_HEADERS, EXTERNAL_AAD, payload])
      end

      def components(message)
        unless message.is_a?(Array) && message.length == 4
          raise FrameError, 'Secure credential must be an untagged COSE_Sign1 array'
        end

        protected_headers, unprotected_headers, payload, signature = message
        validate_protected_headers(protected_headers)
        raise FrameError, 'Credential COSE_Sign1 unprotected headers must be empty' unless unprotected_headers == {}

        validate_payload(payload)
        unless signature.is_a?(String) && signature.encoding == Encoding::BINARY &&
               signature.bytesize == SIGNATURE_BYTES
          raise FrameError, "Credential COSE_Sign1 signature must be #{SIGNATURE_BYTES} bytes"
        end

        message
      end

      def signing_key(private_key)
        OpenSSL::PKey.new_raw_private_key(KEY_TYPE, private_key.byteslice(0, 32))
      end

      def validate_protected_headers(protected_headers)
        unless protected_headers.is_a?(String) && protected_headers.encoding == Encoding::BINARY
          raise FrameError, 'Credential COSE_Sign1 protected headers must be a byte string'
        end
        unless Cbor.decode(protected_headers) == { ALGORITHM_LABEL => EDDSA }
          raise FrameError, 'Credential COSE_Sign1 must protect algorithm EdDSA (-8)'
        end
      rescue FrameError => e
        raise e if e.message.start_with?('Credential COSE_Sign1')

        raise FrameError, "Invalid credential COSE_Sign1 protected headers: #{e.message}"
      end

      def validate_payload(payload)
        return if payload.is_a?(String) && payload.encoding == Encoding::BINARY

        raise FrameError, 'Credential COSE_Sign1 payload must be a byte string'
      end
    end
  end
end
