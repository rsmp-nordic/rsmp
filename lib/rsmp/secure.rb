module RSMP
  # Secure RSMP prototype support.
  module Secure
    PROFILE = 'rsmp-secure-suite0-dev'.freeze
    VERSION = 1
    DEFAULT_MAX_FRAME_SIZE = 65_536
    DEFAULT_HANDSHAKE_TIMEOUT = 2
    DEFAULT_REKEY_AFTER_MESSAGES = 1_000_000
    DEFAULT_REKEY_AFTER_SECONDS = 7_200
    DEFAULT_MIN_REKEY_INTERVAL = 60

    autoload :Cbor, 'rsmp/secure/cbor'
    autoload :FrameIO, 'rsmp/secure/frame_io'
    autoload :Channel, 'rsmp/secure/channel'
    autoload :Transport, 'rsmp/secure/transport'
    autoload :Protocol, 'rsmp/secure/protocol'

    class Error < RSMP::Error; end
    class ConfigurationError < Error; end
    class FrameError < Error; end
    class AuthenticationError < Error; end
    class ReplayError < Error; end

    class << self
      def settings(raw)
        raw = stringify_keys(raw || {})
        {
          'profile' => PROFILE,
          'max_frame_size' => DEFAULT_MAX_FRAME_SIZE,
          'handshake_timeout' => DEFAULT_HANDSHAKE_TIMEOUT,
          'rekey_after_messages' => DEFAULT_REKEY_AFTER_MESSAGES,
          'rekey_after_seconds' => DEFAULT_REKEY_AFTER_SECONDS,
          'min_rekey_interval' => DEFAULT_MIN_REKEY_INTERVAL
        }.merge(raw)
      end

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

      def mode?(raw)
        enabled?(raw) || required?(raw)
      end

      def log_summary(raw)
        return unless mode?(raw)

        "Secure RSMP enabled using profile #{profile(raw)}"
      end

      def handshake_complete_summary(raw, role:, epoch: 0)
        "Secure RSMP E2E handshake complete using profile #{profile(raw)} (#{role}, epoch #{epoch})"
      end

      def rekey_started_summary(raw, role:, epoch:)
        "Secure RSMP E2E rekey started using profile #{profile(raw)} (#{role}, epoch #{epoch})"
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
        protocol.log_e2e_up
        protocol
      end

      private

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, val), memo| memo[key.to_s] = stringify_keys(val) }
        when Array
          value.map { |item| stringify_keys(item) }
        else
          value
        end
      end
    end
  end
end
