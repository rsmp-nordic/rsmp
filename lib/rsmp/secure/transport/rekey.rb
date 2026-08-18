module RSMP
  module Secure
    class Transport
      # Handles mandatory encrypted EDHOC rekey exchanges and responder requests.
      module Rekey
        require_relative 'rekey/validation'
        require_relative 'rekey/policy'

        include Validation
        include Policy

        REKEY_FRAME_RESERVE = 2
        REKEY_ERROR_CODE = 'failed'.freeze
        REKEY_EDHOC_KINDS = %w[rekey_msg1 rekey_msg2 rekey_msg3].freeze
        REKEY_SIMPLE_KINDS = %w[rekey_ack rekey_request].freeze

        private

        def process_rekey_frame(frame)
          receive_channel = rekey_receive_channel(frame)
          attributes = receive_channel.decrypt_control_frame(frame)
          kind = validate_rekey_control(attributes)
          validate_rekey_ack_channel(kind, receive_channel)

          case kind
          when 'rekey_request'
            process_rekey_request(attributes)
          when 'rekey_msg1'
            process_rekey_message1(attributes)
          when 'rekey_error'
            unless @rekeying || @rekey_requested
              raise HandshakeError, "Unsolicited secure rekey error (#{attributes['code']})"
            end

            @rekey_responses.enqueue(attributes)

          else
            raise HandshakeError, 'Unsolicited secure rekey response' unless @rekeying

            @rekey_responses.enqueue(attributes)
          end
        rescue StandardError => e
          fail_transport(e)
          raise
        end

        def execute_rekey_exchange
          validate_rekey_start!

          session = nil
          next_epoch = @channel.next_epoch
          with_rekeying do
            with_rekey_timeout do
              session = build_edhoc_session
              log_secure(Secure.rekey_started_summary(settings, role: role, epoch: next_epoch, peer_id: @peer_id))
              rekey_initiator(session, next_epoch)
            end
          end
        rescue Edhoc::Error, Async::TimeoutError => e
          write_rekey_error(next_epoch)
          raise HandshakeError, "EDHOC rekey failed: #{e.message}"
        rescue StandardError => e
          write_rekey_error(next_epoch) unless peer_rekey_error?(e)
          raise
        ensure
          release_edhoc_session(session) if session
        end

        def rekey_initiator(session, next_epoch)
          write_rekey('rekey_msg1', next_epoch, session.compose_message1)
          session.process_message2(read_rekey_response('rekey_msg2', next_epoch).fetch('edhoc'))
          validate_rekey_peer!(session)
          message3 = session.compose_message3
          next_channel = build_channel(session, epoch: next_epoch, session_id: @channel.session_id)
          @pending_rekey_channel = next_channel
          write_rekey('rekey_msg3', next_epoch, message3)
          read_rekey_response('rekey_ack', next_epoch)
          install_channel(next_channel)
        ensure
          @pending_rekey_channel&.clear! unless @channel.equal?(@pending_rekey_channel)
          @pending_rekey_channel = nil
        end

        def rekey_responder(first_message)
          session = nil
          next_epoch = first_message.fetch('next_epoch')
          with_rekey_timeout do
            session = build_edhoc_session
            start_rekey_responder(session, first_message, next_epoch)
            finish_rekey_responder(session, next_epoch)
          end
        rescue Edhoc::Error, Async::TimeoutError => e
          write_rekey_error(next_epoch)
          raise HandshakeError, "EDHOC rekey failed: #{e.message}"
        rescue StandardError => e
          write_rekey_error(next_epoch) unless peer_rekey_error?(e)
          raise
        ensure
          release_edhoc_session(session) if session
          @rekeying = false
          @rekey_requested = false
          @rekey_done.signal
        end

        def start_rekey_responder(session, first_message, next_epoch)
          validate_rekey_message(first_message, 'rekey_msg1', next_epoch)
          log_secure(Secure.rekey_started_summary(settings, role: role, epoch: next_epoch, peer_id: @peer_id))
          session.process_message1(first_message.fetch('edhoc'))
          write_rekey('rekey_msg2', next_epoch, session.compose_message2)
        end

        def finish_rekey_responder(session, next_epoch)
          session.process_message3(read_rekey_response('rekey_msg3', next_epoch).fetch('edhoc'))
          validate_rekey_peer!(session)
          next_channel = build_channel(session, epoch: next_epoch, session_id: @channel.session_id)
          install_channel(next_channel)
          write_rekey('rekey_ack', next_epoch)
        end

        def start_responder_rekey(first_message)
          raise HandshakeError, 'Secure rekey already in progress' if @rekeying

          @rekeying = true
          @rekey_requested = false
          parent = @task_parent || Async::Task.current
          @responder_rekey = parent.async do |task|
            task.annotate 'secure responder rekey'
            rekey_responder(first_message)
          rescue StandardError => e
            fail_transport(e)
          ensure
            @responder_rekey = nil
          end
        end

        def process_rekey_request(attributes)
          raise FrameError, 'Secure responder received a responder-only rekey request' unless initiator?

          validate_rekey_message(attributes, 'rekey_request', @channel.next_epoch)
          return if @rekeying || @rekey_command_queued

          @rekey_requested = true
          enqueue_internal_rekey(:peer_rekey)
        end

        def process_rekey_message1(attributes)
          raise FrameError, 'Secure initiator received an initiator-only rekey_msg1' if initiator?

          validate_rekey_message(attributes, 'rekey_msg1', @channel.next_epoch)
          start_responder_rekey(attributes)
        end

        def request_rekey_and_wait
          raise HandshakeError, 'Secure initiator must start rekey directly' if initiator?
          return wait_for_rekey if @rekeying

          unless @rekey_requested
            @rekey_requested = true
            write_rekey('rekey_request', @channel.next_epoch)
          end
          wait_for_rekey
        end

        def resolve_pending_rekey_before_send
          if initiator? && @rekey_requested && !@rekeying
            execute_rekey_exchange
          else
            wait_for_rekey
          end
        end

        def schedule_rekey_if_due
          return unless rekey_due?
          return if @rekeying || @rekey_requested || @rekey_command_queued

          @rekey_requested = true
          if initiator?
            enqueue_internal_rekey(:threshold_rekey)
          else
            write_rekey('rekey_request', @channel.next_epoch)
          end
        end

        def renew_if_due!
          return unless rekey_due?

          initiator? ? execute_rekey_exchange : request_rekey_and_wait
        end

        def enqueue_internal_rekey(type)
          @rekey_command_queued = true
          @commands.enqueue(Command.new(type: type))
        rescue Async::Queue::ClosedError
          @rekey_command_queued = false
          raise @error if @error
        end

        def with_rekeying
          @rekeying = true
          @rekey_requested = false
          yield
        ensure
          @rekeying = false
          @rekey_requested = false
          @rekey_done.signal
        end

        def with_rekey_timeout(&)
          Async::Task.current.with_timeout(@settings['rekey_timeout'], &)
        end

        def wait_for_rekey
          @rekey_done.wait while @rekeying || @rekey_requested
          raise_if_failed
        end

        def write_rekey(kind, next_epoch, edhoc = nil)
          attributes = {
            'kind' => kind,
            'next_epoch' => next_epoch
          }
          attributes['edhoc'] = edhoc if edhoc
          write_frame(@channel.encrypt_control(attributes))
        end

        def write_rekey_error(next_epoch)
          return unless next_epoch && @channel

          attributes = {
            'kind' => 'rekey_error',
            'next_epoch' => next_epoch,
            'code' => REKEY_ERROR_CODE
          }
          return unless rekey_error_within_limits?(attributes)

          write_frame(@channel.encrypt_control(attributes))
        rescue StandardError
          nil
        end
      end
    end
  end
end
