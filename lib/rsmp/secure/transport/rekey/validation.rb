module RSMP
  module Secure
    class Transport
      module Rekey
        # Exact shape, role, epoch, and peer-identity checks for rekey controls.
        module Validation
          private

          def validate_rekey_start!
            raise HandshakeError, 'Only the original EDHOC initiator can start secure rekey' unless initiator?
            raise HandshakeError, 'Secure rekey already in progress' if @rekeying
          end

          def rekey_receive_channel(frame)
            pending = @pending_rekey_channel
            return pending if pending && frame['epoch'] == pending.epoch

            @channel
          end

          def validate_rekey_ack_channel(kind, receive_channel)
            return unless kind == 'rekey_ack'
            return if receive_channel.equal?(@pending_rekey_channel)

            raise FrameError, 'rekey_ack must be authenticated with the pending new epoch keys'
          end

          def read_rekey_response(kind, next_epoch)
            attributes = @rekey_responses.dequeue
            if attributes['kind'] == 'rekey_error'
              raise HandshakeError, "Peer rejected secure rekey (#{attributes['code']})"
            end

            validate_rekey_message(attributes, kind, next_epoch)
            attributes
          end

          def validate_rekey_control(attributes)
            raise FrameError, 'Secure rekey message must be a map' unless attributes.is_a?(Hash)

            kind = attributes['kind']
            expected = expected_rekey_keys(attributes, kind)
            raise FrameError, "#{kind} contains unexpected fields" unless attributes.keys.sort == expected

            kind
          end

          def expected_rekey_keys(attributes, kind)
            case kind
            when *REKEY_EDHOC_KINDS
              %w[edhoc kind next_epoch]
            when *REKEY_SIMPLE_KINDS
              %w[kind next_epoch]
            when 'rekey_error'
              raise FrameError, 'Secure rekey error has an invalid code' unless attributes['code'] == REKEY_ERROR_CODE

              %w[code kind next_epoch]
            else
              raise FrameError, "Unknown secure rekey control #{kind.inspect}"
            end
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
            if REKEY_EDHOC_KINDS.include?(kind)
              raise FrameError, 'EDHOC rekey message is missing' unless attributes['edhoc'].is_a?(String)
            elsif attributes.key?('edhoc')
              raise FrameError, "#{kind} must not carry EDHOC bytes"
            end
          end

          def validate_rekey_peer!(session)
            return if session.peer_id == @peer_id

            raise AuthenticationError, 'Secure rekey authenticated a different credential identity'
          end

          def peer_rekey_error?(error)
            error.is_a?(HandshakeError) && error.message.start_with?('Peer rejected secure rekey')
          end
        end
      end
    end
  end
end
