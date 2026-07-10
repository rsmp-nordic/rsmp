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
      CONNECTION_ID = 'single-rsmp-connection'.freeze
      HKDF_HASH = 'SHA256'.freeze
      HKDF_SALT = ''.b.freeze
      HKDF_CONTEXT = 'rsmp-secure-v1 hkdf'.freeze

      attr_reader :role, :session_id, :epoch, :profile, :rsmp_context

      def self.rsmp_context(profile:, initiator_id: nil, responder_id: nil)
        context = {
          'context' => 'rsmp-secure-v1',
          'profile' => context_text(profile),
          'connection' => {
            'socket' => CONNECTION_ID
          }
        }
        context['initiator'] = context_text(initiator_id) if initiator_id
        context['responder'] = context_text(responder_id) if responder_id
        Cbor.encode(context)
      end

      def self.context_text(value)
        text = value.to_s
        text = text.dup.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
        text
      end
      private_class_method :context_text

      def initialize(exporter_secret, role:, epoch: 0, session_id: nil, rsmp_context: nil)
        @role = role.to_sym
        @epoch = epoch
        configure_context(rsmp_context)
        reset_indices
        derive_traffic_secrets(exporter_secret, session_id)
      end

      def encrypt_payload(plaintext)
        @send_idx += 1
        {
          'v' => VERSION,
          'type' => 'data',
          'epoch' => @epoch,
          'idx' => @send_idx,
          'ct' => encrypt(plaintext, @send_key, nonce(@send_nonce_prefix, @send_idx),
                          aad('data', @send_direction, @send_idx))
        }
      end

      def encrypt_control(attributes)
        @send_idx += 1
        {
          'v' => VERSION,
          'type' => 'rekey',
          'epoch' => @epoch,
          'idx' => @send_idx,
          'ct' => encrypt(Cbor.encode(attributes), @send_key, nonce(@send_nonce_prefix, @send_idx),
                          aad('rekey', @send_direction, @send_idx))
        }
      end

      def decrypt_frame(frame)
        validate_data_frame(frame)
        decrypt_validated_frame(frame, 'data')
      end

      def decrypt_control_frame(frame)
        validate_control_frame(frame)
        Cbor.decode(decrypt_validated_frame(frame, 'rekey'))
      end

      def next_epoch
        (@epoch + 1) % 256
      end

      private

      def configure_context(context)
        @rsmp_context = normalize_context(context || self.class.rsmp_context(profile: PROFILE))
        @profile = Cbor.decode(@rsmp_context).fetch('profile')
      end

      def reset_indices
        @send_idx = 0
        @recv_idx = 0
      end

      def derive_traffic_secrets(exporter_secret, session_id)
        @traffic_secret = derive_traffic_secret(exporter_secret)
        @session_id = session_id || derive_labeled_secret(@traffic_secret, 'session id', SESSION_ID_BYTES)
        derive_directional_keys
      end

      def derive_directional_keys
        @send_direction = initiator? ? 'i2r' : 'r2i'
        @recv_direction = initiator? ? 'r2i' : 'i2r'
        @send_key = derive_labeled_secret(@traffic_secret, "#{@send_direction} key", KEY_BYTES)
        @recv_key = derive_labeled_secret(@traffic_secret, "#{@recv_direction} key", KEY_BYTES)
        @send_nonce_prefix = derive_labeled_secret(@traffic_secret, "#{@send_direction} nonce", NONCE_PREFIX_BYTES)
        @recv_nonce_prefix = derive_labeled_secret(@traffic_secret, "#{@recv_direction} nonce", NONCE_PREFIX_BYTES)
      end

      def decrypt_validated_frame(frame, frame_type)
        idx = Integer(frame.fetch('idx'))
        expected = @recv_idx + 1
        raise ReplayError, "Expected secure frame index #{expected}, got #{idx}" unless idx == expected

        plaintext = decrypt(frame.fetch('ct'), @recv_key, nonce(@recv_nonce_prefix, idx),
                            aad(frame_type, @recv_direction, idx))
        @recv_idx = idx
        plaintext
      end

      def initiator?
        role == :initiator
      end

      def normalize_context(context)
        return context if context.is_a?(String)

        Cbor.encode(context)
      end

      def derive_traffic_secret(exporter_secret)
        hkdf(
          exporter_secret,
          Cbor.encode(
            'context' => HKDF_CONTEXT,
            'label' => 'traffic secret',
            'rsmp_context' => @rsmp_context
          ),
          EXPORTER_SECRET_BYTES
        )
      end

      def derive_labeled_secret(secret, label, length)
        hkdf(
          secret,
          Cbor.encode(
            'context' => HKDF_CONTEXT,
            'label' => label
          ),
          length
        )
      end

      def hkdf(secret, info, length)
        OpenSSL::KDF.hkdf(
          secret,
          salt: HKDF_SALT,
          info: info,
          length: length,
          hash: HKDF_HASH
        )
      end

      def nonce(prefix, idx)
        prefix + [idx].pack('N')
      end

      def aad(frame_type, direction, idx)
        Cbor.encode(
          'context' => 'rsmp-secure-data-v1',
          'connection' => CONNECTION_ID,
          'epoch' => @epoch,
          'idx' => idx,
          'sender' => direction,
          'session' => session_id,
          'type' => frame_type
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

      def validate_control_frame(frame)
        raise FrameError, 'Secure frame must be a map' unless frame.is_a?(Hash)
        raise FrameError, "Unexpected secure frame version #{frame['v'].inspect}" unless frame['v'] == VERSION
        raise FrameError, "Unexpected secure frame type #{frame['type'].inspect}" unless frame['type'] == 'rekey'
        raise FrameError, "Unexpected secure epoch #{frame['epoch'].inspect}" unless frame['epoch'] == @epoch
        raise FrameError, 'Secure frame ciphertext is missing' unless frame['ct'].is_a?(String)
      end
    end
  end
end
