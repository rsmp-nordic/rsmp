module RSMP
  class Proxy
    module Modules
      # Message processing functionality. Peer-controlled invalid input is
      # represented by Result::Failure; unexpected implementation errors escape.
      module Receive
        def should_validate_ingoing_message?(message)
          return false if message.is_a?(Version) && !@version_determined
          return true unless @site_settings

          skip = @site_settings['skip_validation']
          return true unless skip

          klass = message.class.name.split('::').last
          !skip.include?(klass)
        end

        def process_deferred
          @node.process_deferred
        end

        def verify_sequence(message)
          expect_version_message(message) unless @version_determined
        end

        def process_packet(json)
          attributes = Message.parse_attributes(json)
          message = Message.build(attributes, json)
          message.attributes['mId'] = attributes['mId'] if message.is_a?(Version)
          process_incoming_message(message)
        rescue InvalidPacket => e
          reject_invalid_packet(json, e)
        rescue MalformedMessage => e
          reject_malformed_version_or_packet(json, attributes, e)
        rescue PeerMessageError => e
          reject_processed_message(message, e)
        rescue HandshakeError, FatalError => e
          reject_fatal_message(message, e)
        ensure
          @node&.clear_deferred
        end

        def reject_malformed_version_or_packet(json, attributes, error)
          if attributes.is_a?(Hash) && attributes['type'] == 'Version' && core_3_3_0_or_newer?
            message = Version.new(attributes)
            message.attributes['mId'] = attributes['mId']
            reject_fatal_message(message, error)
          else
            reject_malformed_packet(json, attributes, error)
          end
        end

        def check_core_3_3_permissions!(message)
          if core_3_3_0_or_newer? && message.is_a?(Alarm) && !use_alarms?
            raise MessageRejected,
                  'Alarm exchange is disabled'
          end
          return unless core_3_3_0_or_newer? && @version_determined && !ready? && application_message?(message)

          raise MessageRejected, 'Communication establishment is incomplete'
        end

        def process_incoming_message(message)
          check_core_3_3_permissions!(message)
          validate = should_validate_ingoing_message?(message)
          if validate
            validation = message.validate(schemas)
            return reject_invalid_message(message, validation) if validation.invalid?
          end

          verify_sequence(message)
          message.decode_for(schemas) if validate
          with_deferred_distribution do
            distribute(message)
            process_message(message)
          end
          process_deferred
          Result.success(message)
        end

        def reject_invalid_packet(json, error)
          reject_packet(
            :invalid_packet,
            "Received invalid packet, expected JSON but got #{json.size} bytes: #{error.message}",
            raw: json
          )
        end

        def reject_malformed_packet(json, attributes, error)
          reject_packet(
            :malformed_message,
            "Received malformed message: #{error.message}",
            raw: json,
            message: Malformed.new(attributes || {})
          )
        end

        def reject_invalid_message(message, validation)
          schemas_string = schemas.map { |schema| "#{schema.first}: #{schema.last}" }.join(', ')
          reason = "schema errors (#{schemas_string}): #{validation.message}"
          text = "Received invalid #{message.type}"
          failure = peer_failure(
            :invalid_peer_message,
            "#{text}: #{validation.message}",
            message: message,
            validation: validation
          )
          publish_peer_failure(failure, message: message)
          log(text, message: message, level: :warning)
          dont_acknowledge(message, text, reason)
          complete_initial_status(message) if respond_to?(:complete_initial_status)
          Result.failure(failure: failure)
        end

        def reject_packet(code, text, raw:, message: nil)
          failure = peer_failure(code, text, message: message, raw: raw)
          publish_peer_failure(failure, message: message)
          log(text, message: message, level: :warning)
          Result.failure(failure: failure)
        end

        def reject_processed_message(message, error)
          code = error.is_a?(MessageRejected) ? :message_rejected : :invalid_peer_message
          text = "Received invalid #{message.type}: #{error.message}"
          failure = peer_failure(code, text, message: message)
          publish_peer_failure(failure, message: message)
          dont_acknowledge(message, "Received invalid #{message.type}", error.message.to_s)
          Result.failure(failure: failure)
        end

        def reject_fatal_message(message, error)
          text = "Rejected #{message&.type || 'message'}: #{error.message}"
          failure = peer_failure(:protocol_failure, text, message: message)
          publish_peer_failure(failure, message: message)
          if message && (!message.is_a?(Version) || valid_received_message_id?(message))
            dont_acknowledge(message, "Rejected #{message.type}", error.message.to_s)
          end
          close(reason: :protocol_failure, failure: failure)
          Result.failure(failure: failure)
        end

        def valid_received_message_id?(message)
          id = message.m_id
          id.is_a?(String) && /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i.match?(id)
        end

        def peer_failure(code, text, message: nil, **context)
          Failure.new(
            code: code,
            message: text,
            source: :peer,
            context: context.merge(message: message).compact
          )
        end

        def publish_peer_failure(failure, message:)
          distribute_event(
            Event.new(
              type: :invalid_message,
              source: self,
              session_id: session_id,
              message: message,
              failure: failure
            )
          )
        end

        def process_message(message)
          case message
          when MessageAck
            process_ack(message)
          when MessageNotAck
            process_not_ack(message)
          when Version
            process_version(message)
          when RSMP::Watchdog
            process_watchdog(message)
          else
            dont_acknowledge(message, 'Received', "unknown message (#{message.type})")
          end
        end

        def will_not_handle(message)
          reason = "since we're a #{self.class.name.downcase}"
          log "Ignoring #{message.type}, #{reason}", message: message, level: :warning
          dont_acknowledge(message, nil, reason)
        end

        def expect_version_message(message)
          return if message.is_a?(Version) || message.is_a?(MessageAck) || message.is_a?(MessageNotAck)

          raise HandshakeError, 'Version must be received first'
        end
      end
    end
  end
end
