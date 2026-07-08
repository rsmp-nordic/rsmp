require 'securerandom'

require_relative 'channel'
require_relative 'frame_io'
require_relative 'protocol_errors'
require_relative 'transport'

module RSMP
  module Secure
    # Secure RSMP protocol wrapper with EDHOC handshake and encrypted CBOR payloads.
    class Protocol
      include ProtocolErrors

      EDHOC_CONNECTION_ID_BYTES = 4

      attr_reader :settings, :role, :matched_peer_id

      def initialize(stream, role:, settings:, log: nil, parent: nil)
        @settings = Secure.settings(settings)
        @role = role.to_sym
        @log = log
        @parent = parent
        validate_settings!
        @frame_io = FrameIO.new(stream, max_frame_size: @settings['max_frame_size'])
        @peek_line = nil
        @channel = nil
        @transport = nil
        @matched_peer_id = nil
      end

      def handshake!
        require 'edhoc'

        session = build_edhoc_session

        if initiator?
          handshake_initiator(session)
        else
          handshake_responder(session)
        end

        @channel = build_channel(session, epoch: 0)
        @matched_peer_id = session.matched_peer_id
        start_transport
        true
      rescue Edhoc::Error => e
        raise HandshakeError, handshake_error_message(e)
      ensure
        release_edhoc_session(session) if session
      end

      def read_line
        return take_peeked if @peek_line

        ensure_ready!
        @transport.read_line
      end

      def peek_line
        @peek_line ||= begin
          ensure_ready!
          @transport.read_line
        end
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
        @transport = nil
        @channel = nil
      end

      def read_frame
        @frame_io.read
      end

      def write_frame(frame)
        @frame_io.write(frame)
      end

      def log_e2ee_up
        ensure_ready!
        @transport.log_e2ee_up
      end

      def channel
        @transport&.channel || @channel
      end

      private

      def initiator?
        role == :initiator
      end

      def ensure_ready!
        raise HandshakeError, 'Secure RSMP handshake is not complete' unless @transport
      end

      def take_peeked
        line = @peek_line
        @peek_line = nil
        line
      end

      def build_edhoc_session
        Edhoc::Suite0Session.new(
          role: role,
          private_key: read_file('private_key'),
          credential: read_file('credential'),
          peers: peer_entries,
          connection_id: SecureRandom.random_bytes(EDHOC_CONNECTION_ID_BYTES)
        )
      end

      def start_transport
        @transport = Transport.new(Transport::Config.new(
                                     frame_io: @frame_io,
                                     role: role,
                                     settings: settings,
                                     channel: @channel,
                                     peer_id: @matched_peer_id,
                                     session_builder: -> { build_edhoc_session },
                                     channel_builder: lambda { |edhoc_session, epoch:, session_id:|
                                       build_channel(edhoc_session, epoch: epoch, session_id: session_id)
                                     },
                                     log: @log,
                                     parent: @parent
                                   )).start
      end

      def handshake_initiator(session)
        write_edhoc(1, session.compose_message1)
        session.process_message2(read_edhoc(2))
        write_edhoc(3, session.compose_message3)
      end

      def handshake_responder(session)
        session.process_message1(read_edhoc(1))
        write_edhoc(2, session.compose_message2)
        session.process_message3(read_edhoc(3))
      end

      def write_edhoc(number, message)
        @frame_io.write(
          'v' => VERSION,
          'type' => 'edhoc',
          'profile' => @settings['profile'],
          'msg' => number,
          'edhoc' => message
        )
      end

      def read_edhoc(number)
        frame = @frame_io.read
        validate_edhoc_frame(frame, number)
        frame.fetch('edhoc')
      end

      def validate_edhoc_frame(frame, number)
        raise FrameError, 'Secure frame must be a map' unless frame.is_a?(Hash)
        raise FrameError, "Expected EDHOC frame #{number}, got #{frame['msg'].inspect}" unless frame['msg'] == number
        raise FrameError, "Expected EDHOC frame, got #{frame['type'].inspect}" unless frame['type'] == 'edhoc'
        raise FrameError, "Unsupported secure profile #{frame['profile'].inspect}" unless frame['profile'] == PROFILE
        raise FrameError, 'EDHOC message is missing' unless frame['edhoc'].is_a?(String)
      end

      def read_file(key)
        path = @settings[key]
        raise ConfigurationError, "secure.#{key} is required" unless path

        read_path(path, key)
      end

      def read_path(path, key)
        path = expand_config_path(path)
        raise ConfigurationError, "secure.#{key} file not found: #{path}" unless File.file?(path)

        File.binread(path)
      end

      def expand_config_path(path)
        Secure.expand_config_path(path, @settings)
      end

      def peer_entries
        @settings['peers'].map do |peer|
          {
            id: peer['id'],
            public_key: read_path(peer_public_key_path(peer), "peers.#{peer['id']}.public_key"),
            credential: read_path(peer_credential_path(peer), "peers.#{peer['id']}.credential")
          }
        end
      end

      def peer_public_key_path(peer)
        peer['public_key']
      end

      def peer_credential_path(peer)
        peer['credential']
      end

      def build_channel(session, epoch:, session_id: nil)
        Channel.new(
          session.export_prk(0, Channel::EXPORTER_SECRET_BYTES),
          role: role,
          epoch: epoch,
          session_id: session_id
        )
      end

      def release_edhoc_session(session)
        session.close if session.respond_to?(:close)
      end

      def validate_settings!
        unless @settings['profile'] == PROFILE
          raise ConfigurationError, "Unsupported secure profile #{@settings['profile'].inspect}"
        end

        %w[private_key credential].each do |key|
          raise ConfigurationError, "secure.#{key} is required" unless @settings[key]
        end

        validate_peer_settings!
      end

      def validate_peer_settings!
        unless @settings['peers']
          raise ConfigurationError, 'secure peer credentials must be configured on the RSMP peer entry'
        end
        raise ConfigurationError, 'secure.peers must not be empty' if @settings['peers'].empty?

        @settings['peers'].each do |peer|
          raise ConfigurationError, 'secure peer public key is required' unless peer_public_key_path(peer)
          raise ConfigurationError, 'secure peer credential is required' unless peer_credential_path(peer)
        end
      end
    end
  end
end
