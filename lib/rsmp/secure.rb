require 'timeout'

module RSMP
  # Secure RSMP authenticated and encrypted transport support.
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
        hash: 'SHA-256',
        edhoc_aead: 'ChaCha20-Poly1305',
        data_aead: 'ChaCha20-Poly1305',
        data_protection: 'COSE_Encrypt0',
        cose_algorithm: 24,
        encoding: 'deterministic CBOR',
        deterministic_cbor: true,
        credential_format: 'exact deterministic-CBOR CCS with an Ed25519 COSE_Key'
      }.freeze
    }.freeze
    IMPLEMENTED_PROFILES = PROFILES.select { |_name, metadata| metadata[:status] == :implemented }.keys.freeze
    VERSION = 1
    DEFAULT_MAX_FRAME_SIZE = 65_536
    DEFAULT_HANDSHAKE_TIMEOUT = 2
    DEFAULT_REKEY_AFTER_MESSAGES = 1_000_000
    DEFAULT_REKEY_AFTER_BYTES = 64 * 1024 * 1024 * 1024
    DEFAULT_REKEY_AFTER_SECONDS = 7_200
    DEFAULT_REKEY_TIMEOUT = 2
    MAX_REKEY_AFTER_MESSAGES = 1_000_000
    MAX_REKEY_AFTER_BYTES = 64 * 1024 * 1024 * 1024
    MAX_REKEY_AFTER_SECONDS = 7_200
    CONFIG_DIR_KEY = '__config_dir'.freeze
    LOCAL_ID_KEY = '__local_id'.freeze
    PEER_ID_KEY = '__credential_id'.freeze
    RSMP_ID_KEY = '__rsmp_id'.freeze
    RSMP_ROLE_KEY = '__rsmp_role'.freeze
    CORE_VERSIONS_KEY = '__core_versions'.freeze
    PEER_SETTING_KEYS = %w[id public_key supervisor_id core_versions].freeze
    DEFAULT_SUPERVISOR_ID = 'supervisor'.freeze
    REVOCATION_LIST_KEY = '__revocation_list'.freeze
    RATE_LIMITER_KEY = '__connection_rate_limiter'.freeze
    RATE_LIMIT_KEY = '__connection_rate_limit_key'.freeze

    require_relative 'secure/configuration'
    extend Configuration

    autoload :Cbor, 'rsmp/secure/cbor'
    autoload :CoseEncrypt0, 'rsmp/secure/cose_encrypt0'
    autoload :Credential, 'rsmp/secure/credential'
    autoload :FrameIO, 'rsmp/secure/frame_io'
    autoload :ProfileCredentials, 'rsmp/secure/profile_credentials'
    autoload :RejectEad, 'rsmp/secure/reject_ead'
    autoload :AuthorizationContext, 'rsmp/secure/authorization_context'
    autoload :Channel, 'rsmp/secure/channel'
    autoload :Transport, 'rsmp/secure/transport'
    autoload :Protocol, 'rsmp/secure/protocol'
    autoload :ConnectionRateLimiter, 'rsmp/secure/connection_rate_limiter'
    autoload :RevocationList, 'rsmp/secure/revocation_list'

    class Error < RSMP::Error; end
    class ConfigurationError < Error; end
    class FrameError < Error; end
    class AuthenticationError < Error; end
    class ReplayError < Error; end
    class RateLimitError < Error; end

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

      def channel_up_summary(raw, role:, epoch:, peer_id: nil)
        return handshake_complete_summary(raw, role: role, epoch: epoch, peer_id: peer_id) if epoch.zero?

        peer = peer_id ? " with peer #{peer_id}" : ''
        "Secure rekey#{peer} complete (#{role}, epoch #{epoch})"
      end

      def failure_summary(stage, error)
        "Secure #{stage} failed (category: #{failure_category(error)})"
      end

      def with_runtime_policy(raw, revocation_list:, rate_limiter: nil, rate_limit_key: nil)
        runtime = {
          REVOCATION_LIST_KEY => revocation_list,
          RATE_LIMITER_KEY => rate_limiter,
          RATE_LIMIT_KEY => rate_limit_key
        }.compact
        (raw || {}).merge(runtime)
      end

      def build_protocol(stream, role:, settings:, task: nil, log: nil)
        require_relative 'secure/protocol'

        settings ||= {}
        check_connection_rate_limit!(settings)
        protocol = Protocol.new(stream, role: role, settings: settings, log: log, parent: task)
        perform_handshake(protocol, task)
        protocol.log_secure_channel_up
        protocol
      rescue StandardError => e
        protocol&.close
        record_connection_failure(settings, e)
        log&.call(failure_summary('handshake', e), level: :warning)
        raise HandshakeError, 'Secure RSMP connection temporarily rate limited' if e.is_a?(RateLimitError)
        raise HandshakeError, 'Secure RSMP handshake timed out' if timeout_error?(e)

        raise
      end

      private

      def timeout_error?(error)
        error.is_a?(Timeout::Error) ||
          (defined?(Async::TimeoutError) && error.is_a?(Async::TimeoutError))
      end

      def failure_category(error)
        return 'rate_limit' if error.is_a?(RateLimitError)
        return 'authentication' if error.is_a?(AuthenticationError)
        return 'replay' if error.is_a?(ReplayError)
        return 'validation' if error.is_a?(FrameError)
        return 'timeout' if timeout_error?(error)
        return 'protocol' if error.is_a?(HandshakeError)
        return 'transport' if error.is_a?(IOError) || error.is_a?(SystemCallError)

        'internal'
      end

      def perform_handshake(protocol, task)
        timeout = protocol.settings['handshake_timeout']
        runner = task || (Async::Task.current? if defined?(Async::Task))
        return runner.with_timeout(timeout) { protocol.handshake! } if runner

        Timeout.timeout(timeout) { protocol.handshake! }
      end

      def check_connection_rate_limit!(settings)
        settings[RATE_LIMITER_KEY]&.check!(settings[RATE_LIMIT_KEY])
      end

      def record_connection_failure(settings, error)
        return if error.is_a?(RateLimitError)

        settings[RATE_LIMITER_KEY]&.record_failure(settings[RATE_LIMIT_KEY])
      end
    end
  end
end
