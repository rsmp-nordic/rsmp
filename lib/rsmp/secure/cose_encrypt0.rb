require 'openssl'
require_relative 'cbor'

module RSMP
  module Secure
    # Minimal Secure RSMP profile of the RFC 9052 COSE_Encrypt0 structure.
    module CoseEncrypt0
      ALGORITHM_LABEL = 1
      PARTIAL_IV_LABEL = 6
      CHACHA20_POLY1305 = 24
      TAG_BYTES = 16
      NONCE_BYTES = 12
      NONCE_PREFIX_BYTES = 8
      MAX_SEQUENCE = (1 << 32) - 1
      PROTECTED_HEADERS = Cbor.encode(ALGORITHM_LABEL => CHACHA20_POLY1305).freeze

      module_function

      def encrypt(plaintext, key:, nonce_prefix:, sequence:, external_aad:)
        partial_iv = encode_partial_iv(sequence)
        ciphertext = aead_encrypt(
          plaintext,
          key,
          nonce(nonce_prefix, partial_iv),
          enc_structure(external_aad)
        )
        [PROTECTED_HEADERS, { PARTIAL_IV_LABEL => partial_iv }, ciphertext]
      end

      def decrypt(message, key:, nonce_prefix:, external_aad:)
        _protected, unprotected, ciphertext = components(message)
        partial_iv = unprotected.fetch(PARTIAL_IV_LABEL)
        aead_decrypt(
          ciphertext,
          key,
          nonce(nonce_prefix, partial_iv),
          enc_structure(external_aad)
        )
      end

      def sequence(message)
        _protected, unprotected, _ciphertext = components(message)
        decode_partial_iv(unprotected.fetch(PARTIAL_IV_LABEL))
      end

      def enc_structure(external_aad)
        unless external_aad.is_a?(String) && external_aad.encoding == Encoding::BINARY
          raise FrameError, 'COSE external AAD must be a byte string'
        end

        Cbor.encode(['Encrypt0', PROTECTED_HEADERS, external_aad])
      end

      def components(message)
        unless message.is_a?(Array) && message.length == 3
          raise FrameError, 'Secure frame enc must be an untagged COSE_Encrypt0 array'
        end

        protected_headers, unprotected_headers, ciphertext = message
        validate_protected_headers(protected_headers)
        validate_unprotected_headers(unprotected_headers)
        unless ciphertext.is_a?(String) && ciphertext.encoding == Encoding::BINARY
          raise FrameError, 'COSE_Encrypt0 ciphertext must be a byte string'
        end
        raise AuthenticationError, 'Ciphertext is too short' if ciphertext.bytesize < TAG_BYTES

        message
      end

      def validate_protected_headers(protected_headers)
        unless protected_headers.is_a?(String) && protected_headers.encoding == Encoding::BINARY
          raise FrameError, 'COSE_Encrypt0 protected headers must be a byte string'
        end
        unless Cbor.decode(protected_headers) == { ALGORITHM_LABEL => CHACHA20_POLY1305 }
          raise FrameError, 'COSE_Encrypt0 must protect algorithm ChaCha20/Poly1305 (24)'
        end
      rescue FrameError => e
        raise e if e.message.start_with?('COSE_Encrypt0')

        raise FrameError, "Invalid COSE_Encrypt0 protected headers: #{e.message}"
      end

      def validate_unprotected_headers(unprotected_headers)
        unless unprotected_headers.is_a?(Hash) && unprotected_headers.keys == [PARTIAL_IV_LABEL]
          raise FrameError, 'COSE_Encrypt0 unprotected headers must contain only Partial IV (6)'
        end

        decode_partial_iv(unprotected_headers.fetch(PARTIAL_IV_LABEL))
      end

      def encode_partial_iv(sequence)
        unless sequence.is_a?(Integer) && sequence.positive? && sequence <= MAX_SEQUENCE
          raise FrameError, "Secure frame index must be between 1 and #{MAX_SEQUENCE}"
        end

        bytes = [sequence].pack('N').bytes.drop_while(&:zero?)
        bytes.pack('C*')
      end

      def decode_partial_iv(partial_iv)
        valid = partial_iv.is_a?(String) && partial_iv.encoding == Encoding::BINARY &&
                partial_iv.bytesize.between?(1, 4) && !partial_iv.getbyte(0).zero?
        raise FrameError, 'COSE_Encrypt0 Partial IV must be a minimal 1-4 byte positive integer' unless valid

        partial_iv.bytes.reduce(0) { |value, byte| (value << 8) | byte }
      end

      def nonce(nonce_prefix, partial_iv)
        unless nonce_prefix.is_a?(String) && nonce_prefix.bytesize == NONCE_PREFIX_BYTES
          raise ConfigurationError, "Secure RSMP nonce prefix must be #{NONCE_PREFIX_BYTES} bytes"
        end

        context_iv = nonce_prefix + ("\0".b * (NONCE_BYTES - NONCE_PREFIX_BYTES))
        padded_partial_iv = partial_iv.rjust(NONCE_BYTES, "\0".b)
        context_iv.bytes.zip(padded_partial_iv.bytes).map { |left, right| left ^ right }.pack('C*')
      end

      def aead_encrypt(plaintext, key, nonce, aad)
        cipher = OpenSSL::Cipher.new('chacha20-poly1305')
        cipher.encrypt
        cipher.key = key
        cipher.iv = nonce
        cipher.auth_data = aad
        ciphertext = cipher.update(plaintext) + cipher.final
        ciphertext + cipher.auth_tag
      end

      def aead_decrypt(ciphertext_with_tag, key, nonce, aad)
        ciphertext = ciphertext_with_tag.byteslice(0, ciphertext_with_tag.bytesize - TAG_BYTES)
        tag = ciphertext_with_tag.byteslice(-TAG_BYTES, TAG_BYTES)
        cipher = OpenSSL::Cipher.new('chacha20-poly1305')
        cipher.decrypt
        cipher.key = key
        cipher.iv = nonce
        cipher.auth_tag = tag
        cipher.auth_data = aad
        cipher.update(ciphertext) + cipher.final
      rescue OpenSSL::Cipher::CipherError
        raise AuthenticationError, 'Secure RSMP authentication failed'
      end
    end
  end
end
