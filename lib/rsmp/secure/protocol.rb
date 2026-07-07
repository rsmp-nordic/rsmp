require 'json'
require_relative 'channel'
require_relative 'frame_io'

module RSMP
  module Secure
    # Secure RSMP protocol wrapper with EDHOC handshake and encrypted CBOR payloads.
    class Protocol
      attr_reader :settings, :role, :channel

      def initialize(stream, role:, settings:)
        @settings = Secure.settings(settings)
        @role = role.to_sym
        validate_settings!
        @frame_io = FrameIO.new(stream, max_frame_size: @settings['max_frame_size'])
        @peek_line = nil
        @channel = nil
      end

      def handshake!
        require 'edhoc'

        session = build_edhoc_session

        if initiator?
          handshake_initiator(session)
        else
          handshake_responder(session)
        end

        @channel = Channel.new(session.export_prk(0, Channel::EXPORTER_SECRET_BYTES), role: role)
        true
      rescue Edhoc::Error => e
        raise HandshakeError, "EDHOC handshake failed: #{e.message}"
      end

      def read_line
        return take_peeked if @peek_line

        read_data_line
      end

      def peek_line
        @peek_line ||= read_data_line
      end

      def write_lines(json)
        ensure_ready!
        attributes = JSON.parse(json)
        plaintext = Cbor.encode(attributes)
        @frame_io.write(@channel.encrypt_payload(plaintext))
      rescue JSON::ParserError => e
        raise InvalidPacket, e.message
      end

      def read_frame
        @frame_io.read
      end

      def write_frame(frame)
        @frame_io.write(frame)
      end

      private

      def initiator?
        role == :initiator
      end

      def ensure_ready!
        raise HandshakeError, 'Secure RSMP handshake is not complete' unless @channel
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
          peer_public_key: read_file('peer_public_key'),
          peer_credential: read_file('peer_credential')
        )
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

      def read_data_line
        ensure_ready!
        attributes = Cbor.decode(@channel.decrypt_frame(@frame_io.read))
        JSON.generate(attributes, array_nl: nil, object_nl: nil, space_before: nil, space: nil)
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
        raise ConfigurationError, "secure.#{key} file not found: #{path}" unless File.file?(path)

        File.binread(path)
      end

      def validate_settings!
        unless @settings['profile'] == PROFILE
          raise ConfigurationError, "Unsupported secure profile #{@settings['profile'].inspect}"
        end

        %w[private_key credential peer_public_key peer_credential].each do |key|
          raise ConfigurationError, "secure.#{key} is required" unless @settings[key]
        end
      end
    end
  end
end
