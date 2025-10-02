# frozen_string_literal: true

module RSMP
  class Proxy
    module Modules
      # Message processing functionality
      # Handles receiving and processing incoming messages
      module MessageProcessing
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
          str = "Received invalid package, must be valid JSON but got #{json.size} bytes: #{e.message}"
          distribute_error e.exception(str)
          log str, level: :warning
          nil
        rescue MalformedMessage => e
          str = "Received malformed message, #{e.message}"
          distribute_error e.exception(str)
          log str, message: Malformed.new(attributes), level: :warning
          # cannot send NotAcknowledged for a malformed message since we can't read it, just ignore it
          nil
        rescue SchemaError, RSMP::Schema::Error => e
          schemas_string = e.schemas.map { |schema| "#{schema.first}: #{schema.last}" }.join(', ')
          reason = "schema errors (#{schemas_string}): #{e.message}"
          str = "Received invalid #{message.type}"
          distribute_error e.exception(str), message: message
          dont_acknowledge message, str, reason
          message
        rescue InvalidMessage => e
          reason = e.message.to_s
          str = "Received invalid #{message.type},"
          distribute_error e.exception("#{str} #{message.json}"), message: message
          dont_acknowledge message, str, reason
          message
        rescue FatalError => e
          reason = e.message
          str = "Rejected #{message.type},"
          distribute_error e.exception(str), message: message
          dont_acknowledge message, str, reason
          close
          message
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
