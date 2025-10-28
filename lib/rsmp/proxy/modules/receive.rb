module RSMP
  class Proxy
    module Modules
      # Message processing functionality
      # Handles receiving and processing incoming messages
      module Receive
        def should_validate_ingoing_message?(message)
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

        def handle_invalid_packet(json, error)
          str = "Received invalid package, must be valid JSON but got #{json.size} bytes: #{error.message}"
          distribute_error error.exception(str)
          log str, level: :warning
          nil
        end

        def handle_malformed_message(attributes, error)
          str = "Received malformed message, #{error.message}"
          distribute_error error.exception(str)
          log str, message: Malformed.new(attributes), level: :warning
          nil
        end

        def handle_schema_error(message, error)
          schemas_string = error.schemas.map { |schema| "#{schema.first}: #{schema.last}" }.join(', ')
          reason = "schema errors (#{schemas_string}): #{error.message}"
          str = "Received invalid #{message.type}"
          distribute_error error.exception(str), message: message
          dont_acknowledge message, str, reason
          message
        end

        def handle_invalid_message(message, error)
          reason = error.message.to_s
          str = "Received invalid #{message.type},"
          distribute_error error.exception("#{str} #{message.json}"), message: message
          dont_acknowledge message, str, reason
          message
        end

        def handle_fatal_error(message, error)
          reason = error.message
          str = "Rejected #{message.type},"
          distribute_error error.exception(str), message: message
          dont_acknowledge message, str, reason
          close
          message
        end

        def process_packet(json)
          attributes = Message.parse_attributes json
          message = Message.build attributes, json
          message.validate(schemas) if should_validate_ingoing_message?(message)
          verify_sequence message
          with_deferred_distribution do
            distribute message
            process_message message
          end
          process_deferred
          message
        rescue InvalidPacket => e
          handle_invalid_packet(json, e)
        rescue MalformedMessage => e
          handle_malformed_message(attributes, e)
        rescue SchemaError, RSMP::Schema::Error => e
          handle_schema_error(message, e)
        rescue InvalidMessage => e
          handle_invalid_message(message, e)
        rescue FatalError => e
          handle_fatal_error(message, e)
        ensure
          @node.clear_deferred
        end

        def process_message(message)
          case message
          when MessageAck
            process_ack message
          when MessageNotAck
            process_not_ack message
          when Version
            process_version message
          when RSMP::Watchdog
            process_watchdog message
          else
            dont_acknowledge message, 'Received', "unknown message (#{message.type})"
          end
        end

        def will_not_handle(message)
          reason ||= "since we're a #{self.class.name.downcase}"
          log "Ignoring #{message.type}, #{reason}", message: message, level: :warning
          dont_acknowledge message, nil, reason
        end

        def expect_version_message(message)
          return if message.is_a?(Version) || message.is_a?(MessageAck) || message.is_a?(MessageNotAck)

          raise HandshakeError, 'Version must be received first'
        end
      end
    end
  end
end
