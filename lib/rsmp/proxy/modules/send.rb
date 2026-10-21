module RSMP
  class Proxy
    module Modules
      # Message sending functionality. Expected operational failures are returned
      # as Result::Failure; unexpected implementation errors are not rescued.
      module Send
        def send_message(message, reason = nil, validate: true, force: false, buffer: true)
          return buffer_or_fail(message, buffer: buffer) unless force || connected?

          written = write_message(message, validate: validate)
          return recover_write_failure(message, written, buffer: buffer) if written.failure?

          expect_acknowledgement(message)
          distribute(message)
          log_send(message, reason)
          Result.success(Delivery.new(message: message, state: :sent))
        end

        def send_message!(...)
          send_message(...).value!
        end

        # Messages constructed by RSMP itself should never fail local schema
        # validation. Surface that as an implementation defect while preserving
        # connection and transport failures as ordinary Result values.
        def send_generated_message(...)
          result = send_message(...)
          result.value! if result.failure&.source == :local
          result
        end

        def write_message(message, validate:)
          return disconnected_send_result(message) unless @protocol

          prepared = prepare_message(message, validate: validate)
          return prepared if prepared.failure?

          write_protocol(message)
        end

        def core_3_3_send_failure(message)
          return unless core_3_3_0_or_newer?
          return 'Alarm exchange is disabled' if message.is_a?(Alarm) && !use_alarms?

          'Communication establishment is incomplete' if !ready? && application_message?(message)
        end

        def nts_attributes?(message)
          message.attributes.key?('cId') || message.is_a?(Alarm) ||
            message.is_a?(AggregatedStatus) || message.is_a?(AggregatedStatusRequest)
        end

        def prepare_message(message, validate:)
          permission = core_3_3_send_failure(message)
          return invalid_outbound_result(message, permission) if permission

          message.direction = :out
          apply_nts_message_attributes(message) if core_3_3_0_or_newer? && nts_attributes?(message)
          message.encode_for(schemas) unless validate == false
          message.generate_json
          unless validate == false
            validation = message.validate(schemas)
            return invalid_outbound_result(message, validation.message, validation: validation) if validation.invalid?
          end
          Result.success(message)
        rescue RSMP::Schema::UnknownMessageCodeError => e
          invalid_outbound_result(message, e.message, cause: e)
        end

        def write_protocol(message)
          @protocol.write_lines(message.json)
          Result.success(message)
        rescue IOError, SystemCallError => e
          Result.failure(
            :disconnected,
            message: "Could not send #{message.type}: #{e.message}",
            source: :transport,
            context: { message: message, session_id: session_id },
            cause: e
          )
        end

        def recover_write_failure(message, result, buffer:)
          return result unless result.failure.code == :disconnected

          buffered = buffer_message(message) if buffer
          return Result.success(Delivery.new(message: buffered, state: :buffered)) if buffered

          result
        end

        def buffer_or_fail(message, buffer:)
          buffered = buffer_message(message) if buffer
          return Result.success(Delivery.new(message: buffered, state: :buffered)) if buffered

          Result.failure(
            :not_ready,
            message: "Cannot send #{message.type}: connection is #{@state}",
            source: :connection,
            context: { message: message, state: @state, session_id: session_id }
          )
        end

        # Base proxies do not buffer. SupervisorProxy's MessageBuffer override
        # returns a cloned queued message when its explicit policy accepts it.
        def buffer_message(message)
          log "Discarded #{message.type}; connection is #{@state}", message: message, level: :warning
          nil
        end

        def disconnected_send_result(message)
          Result.failure(
            :disconnected,
            message: "Cannot send #{message.type}: connection transport is closed",
            source: :transport,
            context: { message: message, session_id: session_id }
          )
        end

        def invalid_outbound_result(message, detail, validation: nil, cause: nil)
          text = "Could not send #{message.type}: #{detail}"
          log(text, message: message, level: :error)
          Result.failure(
            :invalid_outbound_message,
            message: text,
            source: :local,
            context: { message: message, validation: validation }.compact,
            cause: cause
          )
        end

        def log_send(message, reason = nil)
          text = reason ? "Sent #{message.type} #{reason}" : "Sent #{message.type}"
          level = message.type == 'MessageNotAck' ? :warning : :log
          log(text, message: message, level: level)
        end

        def send_message_and_collect(message, collector, validate: true)
          collector.start
          delivery = send_message(message, validate: validate, buffer: false)
          collector.fail(delivery.failure) if delivery.failure?
          collector.wait.map do |collection|
            Exchange.new(request: message, collection: collection)
          end
        ensure
          collector.stop
        end

        def send_message_and_collect!(...)
          send_message_and_collect(...).value!
        end

        def apply_nts_message_attributes(message)
          if core_3_3_0_or_newer?
            message.attributes['ntsOId'] = ''
            message.attributes['xNId'] = ''
            return
          end

          message.attributes['ntsOId'] = main&.ntsoid || ''
          message.attributes['xNId'] = main&.xnid || ''
        end
      end
    end
  end
end
