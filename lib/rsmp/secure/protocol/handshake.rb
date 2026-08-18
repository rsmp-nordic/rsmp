module RSMP
  module Secure
    class Protocol
      # Initial and renewal EDHOC session construction and channel derivation.
      module Handshake
        private

        def build_edhoc_session
          Edhoc::Session.new(
            role: role,
            methods: [0],
            cipher_suites: [4],
            connection_id: SecureRandom.random_bytes(EDHOC_CONNECTION_ID_BYTES),
            credentials: @credentials,
            ead: RejectEad.new,
            max_message_size: @settings['max_frame_size']
          )
        end

        def start_transport
          @transport = Transport.new(Transport::Config.new(
                                       frame_io: @frame_io,
                                       role: role,
                                       settings: settings,
                                       channel: @channel,
                                       peer_id: @authenticated_peer_id,
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
          session.process_message2(read_edhoc(session, 2))
          write_edhoc(3, session.compose_message3)
          session.process_message4(read_edhoc(session, 4))
        end

        def handshake_responder(session)
          session.process_message1(read_edhoc(session, 1))
          write_edhoc(2, session.compose_message2)
          session.process_message3(read_edhoc(session, 3))
          write_edhoc(4, session.compose_message4)
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

        def read_edhoc(session, number)
          frame = @frame_io.read
          process_peer_edhoc_error(session, frame) if frame.is_a?(Hash) && frame['type'] == 'edhoc_error'

          validate_edhoc_frame(frame, number)
          frame.fetch('edhoc')
        end

        def validate_edhoc_frame(frame, number)
          validate_handshake_wrapper!(frame, EDHOC_FRAME_KEYS, 'edhoc')
          @received_valid_handshake_wrapper = true
          raise FrameError, "Expected EDHOC frame #{number}, got #{frame['msg'].inspect}" unless frame['msg'] == number
          raise FrameError, 'EDHOC message is missing' unless frame['edhoc'].is_a?(String)
        end

        def process_peer_edhoc_error(session, frame)
          validate_handshake_wrapper!(frame, EDHOC_ERROR_FRAME_KEYS, 'edhoc_error')
          raise FrameError, 'EDHOC error message is missing' unless frame['edhoc'].is_a?(String)

          @received_valid_handshake_wrapper = true
          @peer_sent_edhoc_error = true
          session.process_error_message(frame.fetch('edhoc'))
          error = session.error_message
          code = error ? error.code : :unspecified
          raise HandshakeError, "Peer rejected EDHOC handshake (#{code})"
        rescue Edhoc::CborError, ArgumentError => e
          raise FrameError, "Invalid EDHOC error message: #{e.message}"
        end

        def validate_handshake_wrapper!(frame, keys, type)
          validate_handshake_shape!(frame, keys)
          validate_handshake_metadata!(frame, type)
        end

        def validate_handshake_shape!(frame, keys)
          raise FrameError, 'Secure frame must be a map' unless frame.is_a?(Hash)
          raise FrameError, 'Secure handshake frame contains unexpected fields' unless frame.keys.sort == keys
        end

        def validate_handshake_metadata!(frame, type)
          raise FrameError, "Unexpected secure frame version #{frame['v'].inspect}" unless frame['v'] == VERSION
          raise FrameError, "Expected #{type} frame, got #{frame['type'].inspect}" unless frame['type'] == type
          return if frame['profile'] == @settings['profile']

          raise FrameError, "Unexpected secure profile #{frame['profile'].inspect}"
        end

        def send_edhoc_error
          return unless @received_valid_handshake_wrapper
          return if @sent_edhoc_error

          @sent_edhoc_error = true
          error = Edhoc::ErrorMessage.new(code: :unspecified, text: GENERIC_EDHOC_ERROR)
          @frame_io.write(
            'v' => VERSION,
            'type' => 'edhoc_error',
            'profile' => @settings['profile'],
            'edhoc' => error.to_bytes
          )
        rescue StandardError
          nil
        end

        def handshake_frame_error_message(error)
          "Secure RSMP handshake failed: #{error.message}"
        end

        def build_channel(session, epoch:, session_id: nil)
          context = rsmp_context
          Channel.new(
            session.export(
              label: Channel::EXPORTER_LABEL,
              context: context,
              length: Channel::EXPORTER_SECRET_BYTES
            ),
            role: role,
            epoch: epoch,
            session_id: session_id,
            rsmp_context: context
          )
        end

        def rsmp_context
          initiator_id = initiator? ? local_id : authenticated_peer_id
          responder_id = initiator? ? authenticated_peer_id : local_id
          Channel.rsmp_context(
            profile: @settings['profile'],
            initiator_id: initiator_id,
            responder_id: responder_id
          )
        end

        def release_edhoc_session(session)
          session.close unless session.closed?
        end
      end
    end
  end
end
