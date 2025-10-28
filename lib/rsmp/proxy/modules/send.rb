module RSMP
  class Proxy
    module Modules
      # Message sending functionality
      # Handles sending messages, validation, and buffering
      module Send
        def handle_send_schema_error(message, error)
          schemas_string = error.schemas.map { |schema| "#{schema.first}: #{schema.last}" }.join(', ')
          str = "Could not send #{message.type} because schema validation failed (#{schemas_string}): #{error.message}"
          log str, message: message, level: :error
          distribute_error error.exception("#{str} #{message.json}")
        end

        def send_message(message, reason = nil, validate: true, force: false)
          raise NotReady if !force && !connected?
          raise IOError unless @protocol

          message.direction = :out
          message.generate_json
          message.validate schemas unless validate == false
          @protocol.write_lines message.json
          expect_acknowledgement message
          distribute message
          log_send message, reason
        rescue IOError
          buffer_message message
        rescue SchemaError, RSMP::Schema::Error => e
          handle_send_schema_error(message, e)
        end

        def buffer_message(message)
          # TODO
          # log "Cannot send #{message.type} because the connection is closed.", message: message, level: :error
        end

        def log_send(message, reason = nil)
          str = if reason
                  "Sent #{message.type} #{reason}"
                else
                  "Sent #{message.type}"
                end

          if message.type == 'MessageNotAck'
            log str, message: message, level: :warning
          else
            log str, message: message, level: :log
          end
        end

        def send_and_optionally_collect(message, options)
          collect_options = options[:collect] || options[:collect!]
          if collect_options
            task = @task.async do |task|
              task.annotate 'send_and_optionally_collect'
              collector = yield collect_options     # call block to create collector
              collector.collect
              collector.ok! if options[:collect!]   # raise any errors if the bang version was specified
              collector
            end

            send_message message, validate: options[:validate]
            { sent: message, collector: task.wait }
          else
            send_message message, validate: options[:validate]
            { sent: message }
          end
        end

        def apply_nts_message_attributes(message)
          message.attributes['ntsOId'] = main && main.ntsoid ? main.ntsoid : ''
          message.attributes['xNId'] = main && main.xnid ? main.xnid : ''
        end
      end
    end
  end
end
