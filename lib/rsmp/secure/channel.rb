require 'openssl'
require_relative 'cbor'
require_relative 'cose_encrypt0'

module RSMP
  module Secure
    # Builds and validates the deterministic application context bound into keys.
    module ChannelContext
      CONNECTION_ID = 'single-rsmp-connection'.freeze
      REQUIRED_KEYS = %w[connection context initiator profile responder].freeze

      module_function

      def encode(profile:, initiator_id:, responder_id:)
        Cbor.encode(
          'context' => 'rsmp-secure-v1',
          'profile' => context_text(profile, 'profile'),
          'initiator' => context_text(initiator_id, 'initiator identity'),
          'responder' => context_text(responder_id, 'responder identity'),
          'connection' => { 'socket' => CONNECTION_ID }
        )
      end

      def normalize(context)
        raise ConfigurationError, 'Secure RSMP exporter context is required' unless context

        bytes = context.is_a?(Hash) ? Cbor.encode(context) : context
        unless bytes.is_a?(String)
          raise ConfigurationError, 'Secure RSMP exporter context must be deterministic CBOR bytes or a map'
        end

        decoded = Cbor.decode(bytes)
        validate(decoded)
        [bytes, decoded.fetch('profile')]
      rescue FrameError => e
        raise ConfigurationError, "Invalid Secure RSMP exporter context: #{e.message}"
      end

      def context_text(value, name)
        raise ConfigurationError, "Secure RSMP #{name} must be a UTF-8 text string" unless value.is_a?(String)

        text = value.dup.force_encoding(Encoding::UTF_8)
        unless text.valid_encoding? && !text.empty?
          raise ConfigurationError, "Secure RSMP #{name} must be a non-empty UTF-8 text string"
        end

        text
      end

      def validate(context)
        valid_shape = context.is_a?(Hash) && context.keys.sort == REQUIRED_KEYS
        unless valid_shape
          raise ConfigurationError, 'Secure RSMP exporter context must contain exactly the v1 context fields'
        end
        unless context.fetch('context') == 'rsmp-secure-v1'
          raise ConfigurationError, 'Secure RSMP exporter context has an unexpected context identifier'
        end
        unless context.fetch('connection') == { 'socket' => CONNECTION_ID }
          raise ConfigurationError, 'Secure RSMP exporter context has an unexpected connection binding'
        end

        validate_text(context.fetch('profile'), 'profile')
        validate_text(context.fetch('initiator'), 'initiator identity')
        validate_text(context.fetch('responder'), 'responder identity')
      end

      def validate_text(value, name)
        valid = value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding? && !value.empty?
        raise ConfigurationError, "Secure RSMP #{name} must be a non-empty CBOR text string" unless valid
      end
    end

    # Encrypts and decrypts Secure RSMP data frames using EDHOC exporter material.
    class Channel
      KEY_BYTES = 32
      NONCE_PREFIX_BYTES = 8
      NONCE_BYTES = 12
      SESSION_ID_BYTES = 16
      EXPORTER_SECRET_BYTES = 32
      EXPORTER_LABEL = 32_768
      TAG_BYTES = CoseEncrypt0::TAG_BYTES
      MAX_SEQUENCE = CoseEncrypt0::MAX_SEQUENCE
      MAX_EPOCH = (1 << 64) - 1
      CONNECTION_ID = ChannelContext::CONNECTION_ID
      HKDF_HASH = 'SHA256'.freeze
      HKDF_SALT = ''.b.freeze
      HKDF_CONTEXT = 'rsmp-secure-v1 hkdf'.freeze

      attr_reader :role, :session_id, :epoch, :profile, :rsmp_context,
                  :sent_frames, :received_frames, :sent_ciphertext_bytes,
                  :received_ciphertext_bytes

      def self.rsmp_context(profile:, initiator_id:, responder_id:)
        ChannelContext.encode(profile: profile, initiator_id: initiator_id, responder_id: responder_id)
      end

      def initialize(exporter_secret, role:, epoch: 0, session_id: nil, rsmp_context: nil)
        @role = role.to_sym
        @epoch = Integer(epoch)
        raise ConfigurationError, "Secure epoch must be between 0 and #{MAX_EPOCH}" unless @epoch.between?(0, MAX_EPOCH)

        configure_context(rsmp_context)
        reset_indices
        reset_usage
        derive_traffic_secrets(exporter_secret, session_id)
      end

      def encrypt_payload(plaintext)
        encrypt_frame('data', plaintext)
      end

      def encrypt_control(attributes)
        encrypt_frame('rekey', Cbor.encode(attributes))
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
        raise FrameError, "Secure epoch exhausted at #{MAX_EPOCH}; reconnect" if @epoch == MAX_EPOCH

        @epoch + 1
      end

      def clear!
        %i[@traffic_secret @send_key @recv_key @send_nonce_prefix @recv_nonce_prefix].each do |name|
          wipe!(instance_variable_get(name))
          instance_variable_set(name, nil)
        end
      end

      private

      def configure_context(context)
        @rsmp_context, @profile = ChannelContext.normalize(context)
      end

      def reset_indices
        @send_idx = 0
        @recv_idx = 0
      end

      def reset_usage
        @sent_frames = 0
        @received_frames = 0
        @sent_ciphertext_bytes = 0
        @received_ciphertext_bytes = 0
      end

      def encrypt_frame(frame_type, plaintext)
        if @send_idx >= MAX_SEQUENCE
          raise FrameError, "Secure frame index exhausted at #{MAX_SEQUENCE}; rekey or reconnect"
        end

        next_idx = @send_idx + 1
        encrypted = CoseEncrypt0.encrypt(
          plaintext,
          key: @send_key,
          nonce_prefix: @send_nonce_prefix,
          sequence: next_idx,
          external_aad: aad(frame_type, @send_direction, next_idx)
        )
        @send_idx = next_idx
        @sent_frames += 1
        @sent_ciphertext_bytes += encrypted.fetch(2).bytesize
        {
          'v' => VERSION,
          'type' => frame_type,
          'epoch' => @epoch,
          'enc' => encrypted
        }
      end

      def derive_traffic_secrets(exporter_secret, session_id)
        @traffic_secret = derive_traffic_secret(exporter_secret)
        @session_id = (session_id || derive_labeled_secret(@traffic_secret, 'session id', SESSION_ID_BYTES)).dup
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
        if @recv_idx >= MAX_SEQUENCE
          raise FrameError, "Secure frame index exhausted at #{MAX_SEQUENCE}; rekey or reconnect"
        end

        encrypted = frame.fetch('enc')
        idx = CoseEncrypt0.sequence(encrypted)
        expected = @recv_idx + 1
        raise ReplayError, "Expected secure frame index #{expected}, got #{idx}" unless idx == expected

        plaintext = CoseEncrypt0.decrypt(
          encrypted,
          key: @recv_key,
          nonce_prefix: @recv_nonce_prefix,
          external_aad: aad(frame_type, @recv_direction, idx)
        )
        @recv_idx = idx
        @received_frames += 1
        @received_ciphertext_bytes += encrypted.fetch(2).bytesize
        plaintext
      end

      def initiator?
        role == :initiator
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

      def validate_data_frame(frame)
        validate_encrypted_frame(frame, 'data')
      end

      def validate_control_frame(frame)
        validate_encrypted_frame(frame, 'rekey')
      end

      def validate_encrypted_frame(frame, type)
        raise FrameError, 'Secure frame must be a map' unless frame.is_a?(Hash)
        unless frame.keys.sort == %w[enc epoch type v]
          raise FrameError, "Secure #{type} frame contains unexpected fields"
        end

        validate_encrypted_frame_metadata(frame, type)
      end

      def validate_encrypted_frame_metadata(frame, type)
        raise FrameError, "Unexpected secure frame version #{frame['v'].inspect}" unless frame['v'] == VERSION
        raise FrameError, "Unexpected secure frame type #{frame['type'].inspect}" unless frame['type'] == type
        raise FrameError, "Unexpected secure epoch #{frame['epoch'].inspect}" unless frame['epoch'] == @epoch
        raise FrameError, 'Secure frame COSE_Encrypt0 object is missing' unless frame['enc'].is_a?(Array)
      end

      def wipe!(value)
        return unless value.is_a?(String) && !value.frozen?

        value.replace("\0" * value.bytesize)
        value.clear
      end
    end
  end
end
