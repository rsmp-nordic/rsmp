require 'openssl'
require_relative 'cbor'

module RSMP
  module Secure
    # Encrypts and decrypts Secure RSMP data frames using EDHOC exporter material.
    class Channel
      KEY_BYTES = 32
      NONCE_PREFIX_BYTES = 8
      NONCE_BYTES = 12
      SESSION_ID_BYTES = 16
      EXPORTER_SECRET_BYTES = 32
      TAG_BYTES = 16

      attr_reader :role, :session_id

      def initialize(exporter_secret, role:)
        @role = role.to_sym
        @epoch = 0
        @send_idx = 0
        @recv_idx = 0
        @session_id = expand(exporter_secret, 'session id', SESSION_ID_BYTES)

        @send_direction = initiator? ? 'i2r' : 'r2i'
        @recv_direction = initiator? ? 'r2i' : 'i2r'
        @send_key = expand(exporter_secret, "#{@send_direction} key", KEY_BYTES)
        @recv_key = expand(exporter_secret, "#{@recv_direction} key", KEY_BYTES)
        @send_nonce_prefix = expand(exporter_secret, "#{@send_direction} nonce", NONCE_PREFIX_BYTES)
        @recv_nonce_prefix = expand(exporter_secret, "#{@recv_direction} nonce", NONCE_PREFIX_BYTES)
      end

      def encrypt_payload(plaintext)
        @send_idx += 1
        {
          'v' => VERSION,
          'type' => 'data',
          'epoch' => @epoch,
          'idx' => @send_idx,
          'ct' => encrypt(plaintext, @send_key, nonce(@send_nonce_prefix, @send_idx),
                          aad(@send_direction, @send_idx))
        }
      end

      def decrypt_frame(frame)
        validate_data_frame(frame)
        idx = Integer(frame.fetch('idx'))
        expected = @recv_idx + 1
        raise ReplayError, "Expected secure data index #{expected}, got #{idx}" unless idx == expected

        plaintext = decrypt(frame.fetch('ct'), @recv_key, nonce(@recv_nonce_prefix, idx), aad(@recv_direction, idx))
        @recv_idx = idx
        plaintext
      end

      private

      def initiator?
        role == :initiator
      end

      def expand(secret, label, length)
        OpenSSL::KDF.hkdf(
          secret,
          salt: '',
          info: "#{PROFILE} #{label}",
          length: length,
          hash: 'SHA256'
        )
      end

      def nonce(prefix, idx)
        prefix + [idx].pack('N')
      end

      def aad(direction, idx)
        Cbor.encode(
          'v' => VERSION,
          'profile' => PROFILE,
          'type' => 'data',
          'session' => session_id,
          'direction' => direction,
          'epoch' => @epoch,
          'idx' => idx
        )
      end

      def encrypt(plaintext, key, nonce, aad)
        cipher = OpenSSL::Cipher.new('chacha20-poly1305')
        cipher.encrypt
        cipher.key = key
        cipher.iv = nonce
        cipher.auth_data = aad
        ciphertext = cipher.update(plaintext) + cipher.final
        ciphertext + cipher.auth_tag
      end

      def decrypt(ciphertext_with_tag, key, nonce, aad)
        raise AuthenticationError, 'Ciphertext is too short' if ciphertext_with_tag.bytesize < TAG_BYTES

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

      def validate_data_frame(frame)
        raise FrameError, 'Secure frame must be a map' unless frame.is_a?(Hash)
        raise FrameError, "Unexpected secure frame version #{frame['v'].inspect}" unless frame['v'] == VERSION
        raise FrameError, "Unexpected secure frame type #{frame['type'].inspect}" unless frame['type'] == 'data'
        raise FrameError, "Unexpected secure epoch #{frame['epoch'].inspect}" unless frame['epoch'] == @epoch
        raise FrameError, 'Secure frame ciphertext is missing' unless frame['ct'].is_a?(String)
      end
    end
  end
end
