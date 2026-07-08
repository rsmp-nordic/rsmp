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
    CONFIG_DIR_KEY = '__config_dir'.freeze
    PEER_SETTING_KEYS = %w[id public_key supervisor_id].freeze
    DEFAULT_SUPERVISOR_ID = 'supervisor'.freeze

    require_relative 'secure/configuration'
    extend Configuration

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
        protocol.log_e2ee_up
        protocol
      end
    end
  end
end
