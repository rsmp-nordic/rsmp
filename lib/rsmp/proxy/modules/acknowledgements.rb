module RSMP
  class Proxy
    module Modules
      # Message acknowledgement handling
      # Manages sending/receiving acks and nacks, and tracking acknowledged messages
      module Acknowledgements
        def acknowledge(original)
          raise InvalidArgument unless original

          ack = MessageAck.build_from(original)
          ack.original = original.clone
          send_message ack, "for #{ack.original.type} #{original.m_id_short}"
          check_ingoing_acknowledged original
        end

        def dont_acknowledge(original, prefix = nil, reason = nil, force: true)
          raise InvalidArgument unless original

          str = [prefix, reason].join(' ')
          log str, message: original, level: :warning if reason
          message = MessageNotAck.new({
                                        'oMId' => original.m_id,
                                        'rea' => reason || 'Unknown reason'
                                      })
          message.original = original.clone
          send_message message, "for #{original.type} #{original.m_id_short}", force: force
        end

        def expect_acknowledgement(message)
          return if message.is_a?(MessageAck) || message.is_a?(MessageNotAck)

          @awaiting_acknowledgement[message.m_id] = message
        end

        def dont_expect_acknowledgement(message)
          @awaiting_acknowledgement.delete message.attribute('oMId')
        end

        def check_ack_timeout(now)
          timeout = @site_settings['timeouts']['acknowledgement']
          # hash cannot be modify during iteration, so clone it
          @awaiting_acknowledgement.clone.each_pair do |_m_id, message|
            latest = message.timestamp + timeout
            next unless now > latest

            str = "No acknowledgements for #{message.type} #{message.m_id_short} within #{timeout} seconds"
            log str, level: :error
            begin
              close
            ensure
              distribute_error MissingAcknowledgment.new(str)
            end
          end
        end

        def find_original_for_message(message)
          @awaiting_acknowledgement[message.attribute('oMId')]
        end

        # TODO: this might be better handled by a proper event machine using e.g. the EventMachine gem
        def check_outgoing_acknowledged(message)
          return if @outgoing_acknowledged[message.type]

          @outgoing_acknowledged[message.type] = true
          acknowledged_first_outgoing message
        end

        def check_ingoing_acknowledged(message)
          return if @ingoing_acknowledged[message.type]

          @ingoing_acknowledged[message.type] = true
          acknowledged_first_ingoing message
        end

        def acknowledged_first_outgoing(message); end

        def acknowledged_first_ingoing(message); end

        def process_ack(message)
          original = find_original_for_message message
          if original
            dont_expect_acknowledgement message
            message.original = original
            log_acknowledgement_for_original message, original

            case original.type
            when 'Version'
              version_acknowledged
            when 'StatusSubscribe'
              status_subscribe_acknowledged original
            end

            check_outgoing_acknowledged original

            @acknowledgements[original.m_id] = message
            @acknowledgement_condition.signal message
          else
            log_acknowledgement_for_unknown message
          end
        end

        def process_not_ack(message)
          original = find_original_for_message message
          if original
            dont_expect_acknowledgement message
            message.original = original
            log_acknowledgement_for_original message, original
            @acknowledgements[original.m_id] = message
            @acknowledgement_condition.signal message
          else
            log_acknowledgement_for_unknown message
          end
        end

        def log_acknowledgement_for_original(message, original)
          str = "Received #{message.type} for #{original.type} #{message.attribute('oMId')[0..3]}"
          if message.type == 'MessageNotAck'
            reason = message.attributes['rea']
            str = "#{str}: #{reason}" if reason
            log str, message: message, level: :warning
          else
            log str, message: message, level: :log
          end
        end

        def log_acknowledgement_for_unknown(message)
          log "Received #{message.type} for unknown message #{message.attribute('oMId')[0..3]}", message: message,
                                                                                                 level: :warning
        end

        def status_subscribe_acknowledged(original)
          component = find_component original.attribute('cId')
          return unless component

          short = Message.shorten_m_id original.m_id
          subscribe_list = original.attributes['sS']
          log "StatusSubscribe #{short} acknowledged, allowing repeated status values for #{subscribe_list}",
              level: :info
          component.allow_repeat_updates subscribe_list
        end
      end
    end
  end
end
