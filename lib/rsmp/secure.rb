module RSMP
  # Secure RSMP prototype support.
  module Secure
    PROFILE = 'rsmp-secure-v1'.freeze
    V1_PROFILE = PROFILE
    PROFILES = {
      PROFILE => {
        status: :implemented,
        edhoc_method: 0,
        edhoc_cipher_suite: 4,
        edhoc_exporter_label: 32_768,
        ecdh: 'X25519',
        signature: 'Ed25519/EdDSA',
        credential_signature_algorithm: -19,
        hash: 'SHA-256',
        edhoc_aead: 'ChaCha20-Poly1305',
        data_aead: 'ChaCha20-Poly1305',
        data_protection: 'COSE_Encrypt0',
        cose_algorithm: 24,
        encoding: 'deterministic CBOR',
        deterministic_cbor: true,
        credential_format: 'COSE_Sign1 CBOR bundle with EDHOC KID/CCS credential'
      }.freeze
    }.freeze
    IMPLEMENTED_PROFILES = PROFILES.select { |_name, metadata| metadata[:status] == :implemented }.keys.freeze
    VERSION = 1
    DEFAULT_MAX_FRAME_SIZE = 65_536
    DEFAULT_HANDSHAKE_TIMEOUT = 2
    DEFAULT_REKEY_AFTER_MESSAGES = 1_000_000
    DEFAULT_REKEY_AFTER_SECONDS = 7_200
    DEFAULT_MIN_REKEY_INTERVAL = 60
    CONFIG_DIR_KEY = '__config_dir'.freeze
    LOCAL_ID_KEY = '__local_id'.freeze
    PEER_ID_KEY = '__credential_id'.freeze
    PEER_SETTING_KEYS = %w[id public_key supervisor_id].freeze
    DEFAULT_SUPERVISOR_ID = 'supervisor'.freeze

    require_relative 'secure/configuration'
    extend Configuration

    autoload :Cbor, 'rsmp/secure/cbor'
    autoload :CoseEncrypt0, 'rsmp/secure/cose_encrypt0'
    autoload :CoseSign1, 'rsmp/secure/cose_sign1'
    autoload :CredentialBundle, 'rsmp/secure/credential_bundle'
    autoload :FrameIO, 'rsmp/secure/frame_io'
    autoload :ProfileCredentials, 'rsmp/secure/profile_credentials'
    autoload :Channel, 'rsmp/secure/channel'
    autoload :Transport, 'rsmp/secure/transport'
    autoload :Protocol, 'rsmp/secure/protocol'

    class Error < RSMP::Error; end
    class ConfigurationError < Error; end
    class FrameError < Error; end
    class AuthenticationError < Error; end
    class ReplayError < Error; end

    class << self
      def enabled?(raw)
        settings = raw || {}
        settings['enabled'] == true || settings['required'] == true
      end

      def required?(raw)
        raw && raw['required'] == true
      end

      def profile(raw)
        settings(raw)['profile']
      end

      def profile_metadata(name)
        PROFILES[name]
      end

      def implemented_profile?(name)
        IMPLEMENTED_PROFILES.include?(name)
      end

      def profile_status(name)
        profile_metadata(name)&.fetch(:status)
      end

      def validate_profile_name!(name)
        if implemented_profile?(name)
          true
        elsif profile_status(name) == :planned
          raise RSMP::ConfigurationError, "Secure profile #{name.inspect} is planned but not implemented"
        else
          raise RSMP::ConfigurationError, "Unsupported secure profile #{name.inspect}"
        end
      end

      def edhoc_session_class(name)
        case name
        when PROFILE
          Edhoc::Suite4Session
        else
          raise ConfigurationError, "Unsupported secure profile #{name.inspect}"
        end
      end

      def mode?(raw)
        enabled?(raw) || required?(raw)
      end

      def log_summary(raw)
        return unless mode?(raw)

        "Secure profile #{profile(raw)}"
      end

      def handshake_complete_summary(_raw, role:, epoch: 0, peer_id: nil)
        peer = peer_id ? " with peer #{peer_id}" : ''
        "Secure handshake#{peer} complete (#{role}, epoch #{epoch})"
      end

      def rekey_started_summary(_raw, role:, epoch:, peer_id: nil)
        peer = peer_id ? " with peer #{peer_id}" : ''
        "Secure rekey#{peer} started (#{role}, epoch #{epoch})"
      end

      def build_protocol(stream, role:, settings:, task: nil, log: nil)
        require_relative 'secure/protocol'

        protocol = Protocol.new(stream, role: role, settings: settings, log: log, parent: task)
        timeout = protocol.settings['handshake_timeout']
        if task
          task.with_timeout(timeout) { protocol.handshake! }
        else
          protocol.handshake!
        end
        protocol.log_secure_channel_up
        protocol
      end
    end
  end
end
