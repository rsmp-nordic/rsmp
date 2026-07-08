module RSMP
  module Secure
    class Transport
      # Handles encrypted EDHOC rekey control frames inside the transport.
      module Rekey
        private

        def process_rekey_frame(frame)
          attributes = @channel.decrypt_control_frame(frame)
          if !initiator? && attributes['kind'] == 'rekey_msg1'
            start_responder_rekey(attributes)
          else
            @rekey_responses.enqueue(attributes)
          end
        rescue StandardError => e
          fail_transport(e)
        end

        def execute_rekey_exchange
          raise HandshakeError, 'Secure rekey already in progress' if @rekeying

          session = nil
          with_rekeying do
            session = build_edhoc_session
            next_epoch = @channel.next_epoch
            log_secure(Secure.rekey_started_summary(settings, role: role, epoch: next_epoch, peer_id: @peer_id))
            rekey_initiator(session, next_epoch)
          end
        rescue Edhoc::Error => e
          raise HandshakeError, "EDHOC rekey failed: #{e.message}"
        ensure
          release_edhoc_session(session) if session
        end

        def rekey_initiator(session, next_epoch)
          write_rekey('rekey_msg1', next_epoch, session.compose_message1)
          session.process_message2(read_rekey_response('rekey_msg2', next_epoch).fetch('edhoc'))
          write_rekey('rekey_msg3', next_epoch, session.compose_message3)
          next_channel = build_channel(session, epoch: next_epoch, session_id: @channel.session_id)
          write_rekey('rekey_commit', next_epoch)
          install_channel(next_channel)
        end

        def rekey_responder(first_message)
          session = nil
          session = build_edhoc_session
          next_epoch = start_rekey_responder(session, first_message)
          finish_rekey_responder(session, next_epoch)
        rescue Edhoc::Error => e
          raise HandshakeError, "EDHOC rekey failed: #{e.message}"
        ensure
          release_edhoc_session(session) if session
          @rekeying = false
          @rekey_done.signal
        end

        def start_rekey_responder(session, first_message)
          next_epoch = first_message.fetch('next_epoch')
          validate_rekey_message(first_message, 'rekey_msg1', next_epoch)
          log_secure(Secure.rekey_started_summary(settings, role: role, epoch: next_epoch, peer_id: @peer_id))
          session.process_message1(first_message.fetch('edhoc'))
          write_rekey('rekey_msg2', next_epoch, session.compose_message2)
          next_epoch
        end

        def finish_rekey_responder(session, next_epoch)
          session.process_message3(read_rekey_response('rekey_msg3', next_epoch).fetch('edhoc'))
          next_channel = build_channel(session, epoch: next_epoch, session_id: @channel.session_id)
          read_rekey_response('rekey_commit', next_epoch)
          install_channel(next_channel)
        end

        def start_responder_rekey(first_message)
          raise HandshakeError, 'Secure rekey already in progress' if @rekeying

          @rekeying = true
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

        def with_rekeying
          @rekeying = true
          yield
        ensure
          @rekeying = false
          @rekey_done.signal
        end

        def wait_for_rekey
          @rekey_done.wait while @rekeying
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

        def read_rekey_response(kind, next_epoch)
          attributes = @rekey_responses.dequeue
          validate_rekey_message(attributes, kind, next_epoch)
          attributes
        end

        def validate_rekey_message(attributes, kind, next_epoch)
          raise FrameError, 'Secure rekey message must be a map' unless attributes.is_a?(Hash)
          raise FrameError, "Expected #{kind}, got #{attributes['kind'].inspect}" unless attributes['kind'] == kind
          unless attributes['next_epoch'] == next_epoch
            raise FrameError, "Expected rekey epoch #{next_epoch}, got #{attributes['next_epoch'].inspect}"
          end

          validate_rekey_edhoc(attributes, kind)
        end

        def validate_rekey_edhoc(attributes, kind)
          if kind.start_with?('rekey_msg')
            raise FrameError, 'EDHOC rekey message is missing' unless attributes['edhoc'].is_a?(String)
          elsif attributes.key?('edhoc')
            raise FrameError, "#{kind} must not carry EDHOC bytes"
          end
        end

        def install_channel(channel)
          @channel = channel
          @epoch_started_at = monotonic_now
          @last_rekey_at = @epoch_started_at
          @data_sent_in_epoch = 0
          log_e2ee_up
        end

        def maybe_rekey!
          return unless initiator?
          return if @channel.epoch.zero? && @data_sent_in_epoch.zero?
          return unless rekey_due?
          return unless min_rekey_interval_elapsed?

          execute_rekey_exchange
        end

        def rekey_due?
          message_threshold = @settings['rekey_after_messages']
          time_threshold = @settings['rekey_after_seconds']
          message_rekey_due?(message_threshold) || time_rekey_due?(time_threshold)
        end

        def message_rekey_due?(threshold)
          threshold && @data_sent_in_epoch >= threshold
        end

        def time_rekey_due?(threshold)
          threshold && (monotonic_now - @epoch_started_at) >= threshold
        end

        def min_rekey_interval_elapsed?
          minimum = @settings['min_rekey_interval']
          return true unless minimum
          return true unless @last_rekey_at

          (monotonic_now - @last_rekey_at) >= minimum
        end
      end
    end
  end
end
