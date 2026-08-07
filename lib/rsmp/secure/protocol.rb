require 'securerandom'

require_relative 'channel'
require_relative 'frame_io'
require_relative 'protocol_errors'
require_relative 'protocol/handshake'
require_relative 'transport'

module RSMP
  module Secure
    # Secure RSMP protocol wrapper with EDHOC authentication and encrypted CBOR payloads.
    class Protocol
      include ProtocolErrors
      include Handshake

      EDHOC_CONNECTION_ID_BYTES = 4
      EDHOC_FRAME_KEYS = %w[edhoc msg profile type v].freeze
      EDHOC_ERROR_FRAME_KEYS = %w[edhoc profile type v].freeze
      PRE_AUTHORIZATION_TYPES = %w[MessageAck MessageNotAck Version].freeze
      GENERIC_EDHOC_ERROR = 'EDHOC handshake failed'.freeze

      attr_reader :settings, :role, :authenticated_peer_id, :local_id, :authorization_context

      def initialize(stream, role:, settings:, log: nil, parent: nil)
        @settings = Secure.settings(settings)
        @role = role.to_sym
        @log = log
        @parent = parent
        validate_settings!
        @credentials = ProfileCredentials.new(@settings)
        @credentials.validate!
        @local_id = @credentials.local_id
        @frame_io = FrameIO.new(stream, max_frame_size: @settings['max_frame_size'])
        @peek_line = nil
        @channel = nil
        @transport = nil
        @authenticated_peer_id = nil
        @authorization_context = nil
        @received_valid_handshake_wrapper = false
        @sent_edhoc_error = false
        @peer_sent_edhoc_error = false
      end

      def handshake!
        require 'edhoc'

        session = build_edhoc_session
        initiator? ? handshake_initiator(session) : handshake_responder(session)

        @authenticated_peer_id = session.peer_id
        unless @authenticated_peer_id
          raise AuthenticationError,
                'EDHOC completed without an authenticated peer identity'
        end

        @channel = build_channel(session, epoch: 0)
        start_transport
        true
      rescue Edhoc::Error => e
        send_edhoc_error unless @peer_sent_edhoc_error
        raise HandshakeError, handshake_error_message(e)
      rescue FrameError => e
        send_edhoc_error unless @peer_sent_edhoc_error
        raise HandshakeError, handshake_frame_error_message(e)
      ensure
        release_edhoc_session(session) if session
      end

      def authorize!(rsmp_id:, core_version:)
        ensure_ready!
        candidate = build_authorization_context(rsmp_id, core_version)
        validate_unchanged_authorization!(candidate)

        @authorization_context ||= candidate
        true
      rescue AuthenticationError
        close
        raise
      end

      def read_line
        @peek_line ? take_peeked : read_and_validate_line
      end

      def peek_line
        @peek_line ||= read_and_validate_line
      end

      def write_lines(json)
        ensure_ready!
        @transport.write_lines(json)
      end

      def rekey!
        ensure_ready!
        @transport.rekey!
      end

      def close
        @transport&.close
        @channel&.clear!
        @credentials&.clear!
        @transport = nil
        @channel = nil
        @authorization_context = nil
        @peek_line = nil
      end

      def read_frame
        @frame_io.read
      end

      def write_frame(frame)
        @frame_io.write(frame)
      end

      def log_secure_channel_up
        ensure_ready!
        @transport.log_secure_channel_up
      end

      def channel
        @transport&.channel || @channel
      end

      def traffic_stats
        @frame_io.traffic_stats
      end

      private

      def initiator?
        role == :initiator
      end

      def ensure_ready!
        raise HandshakeError, 'Secure RSMP handshake is not complete' unless @transport
      end

      def build_authorization_context(rsmp_id, core_version)
        peer = @credentials.peer(authenticated_peer_id)
        raise AuthenticationError, 'Authenticated peer is no longer in the trust store' unless peer

        normalized_id = authorization_text(rsmp_id, 'identity')
        normalized_version = authorization_text(core_version, 'Core version')
        validate_authorized_identity!(peer, normalized_id)
        validate_authorized_core!(peer, normalized_version)
        AuthorizationContext.new(
          credential_id: authenticated_peer_id,
          rsmp_id: normalized_id,
          role: peer.rsmp_role,
          core_version: normalized_version
        )
      end

      def validate_authorized_identity!(peer, identity)
        return if identity == peer.rsmp_id

        raise AuthenticationError,
              "Secure credential #{authenticated_peer_id.inspect} is not authorized for RSMP identity " \
              "#{identity.inspect}"
      end

      def validate_authorized_core!(peer, core_version)
        return if peer.core_versions.empty? || peer.core_versions.include?(core_version)

        raise AuthenticationError,
              "Secure credential #{authenticated_peer_id.inspect} is not authorized for Core " \
              "#{core_version.inspect}"
      end

      def validate_unchanged_authorization!(candidate)
        return unless @authorization_context
        return if @authorization_context.to_h == candidate.to_h

        raise AuthenticationError, 'Secure RSMP authorization context cannot change on an established connection'
      end

      def take_peeked
        line = @peek_line
        @peek_line = nil
        line
      end

      def read_and_validate_line
        ensure_ready!
        line = @transport.read_line
        attributes = JSON.parse(line)
        raise FrameError, 'Decrypted RSMP message must be an object' unless attributes.is_a?(Hash)

        type = attributes['type']
        if authorization_context
          raise AuthenticationError, 'RSMP Version cannot change after secure authorization' if type == 'Version'
        elsif !PRE_AUTHORIZATION_TYPES.include?(type)
          raise AuthenticationError, "RSMP #{type.inspect} is not permitted before secure authorization"
        end
        line
      rescue JSON::ParserError => e
        raise FrameError, "Invalid decrypted RSMP JSON: #{e.message}"
      rescue AuthenticationError, FrameError
        close
        raise
      end

      def validate_settings!
        Secure.validate_profile_name!(@settings['profile'])
        Secure.validate_rekey_settings!(@settings)

        %w[private_key credential].each do |key|
          raise ConfigurationError, "secure.#{key} is required" unless @settings[key]
        end

        peers = @settings['peers']
        raise ConfigurationError, 'secure peer credentials must be configured on the RSMP peer entry' unless peers
        raise ConfigurationError, 'secure.peers must not be empty' if peers.empty?

        peers.each do |peer|
          raise ConfigurationError, 'secure peer credential is required' unless peer['credential']
        end
      end

      def authorization_text(value, name)
        text = value.dup.force_encoding(Encoding::UTF_8) if value.is_a?(String)
        valid = text&.valid_encoding? && !text.empty?
        raise AuthenticationError, "Secure RSMP #{name} must be a non-empty UTF-8 string" unless valid

        text
      end
    end
  end
end
