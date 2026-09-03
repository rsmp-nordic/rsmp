module RSMP
  class Proxy
    module Modules
      # Owns one connection session and translates expected termination into
      # lifecycle events without swallowing unexpected task exceptions.
      module Lifecycle
        def disconnect
          close(reason: :local_stop)
          Result.success(self)
        end

        def disconnect!
          disconnect.value!
        end

        def connect!
          connect.value!
        end

        def wait_for_reader
          wait_for_session
        end

        def begin_session
          clear
          @session_id += 1
          @session_closed = false
          @session_id
        end

        def close(reason: :peer_closed, failure: nil, session_id: @session_id)
          return if session_id != @session_id || @session_closed

          @session_closed = true
          log 'Closing connection', level: :warning
          close_stream
          close_socket
          stop_reader
          self.state = :disconnected
          publish_connection_end(reason, failure, session_id)
          stop_timer
        end

        def stop_subtasks
          stop_timer
          stop_reader
          clear
          super
        end

        def stop_timer
          current = Async::Task.current?
          @timer&.cancel unless @timer.equal?(current)
        ensure
          @timer = nil
        end

        def stop_reader
          current = Async::Task.current?
          @reader&.cancel unless @reader.equal?(current)
        ensure
          @reader = nil
        end

        def close_stream
          @stream&.close
        ensure
          @stream = nil
        end

        def close_socket
          @socket&.close
        ensure
          @socket = nil
        end

        def stop_task
          close(reason: :local_stop)
          super
        end

        def distribute_event(event)
          super
          @node&.publish_event(event)
          event
        end

        def connection_end_failure(reason)
          local = reason == :local_stop
          Failure.new(
            code: local ? :cancelled : :disconnected,
            message: "Connection ended (#{reason})",
            source: local ? :local : :connection,
            context: { reason: reason, session_id: @session_id }
          )
        end

        def close_from_result(result)
          return close(reason: :peer_closed) if result.nil? || result.success?

          reason = result.failure.context[:reason] || :transport_failure
          close(reason: reason, failure: result.failure)
        end

        def publish_connection_attempt_failure(failure)
          log failure.message, level: :warning
          distribute_event(
            Event.new(
              type: :connection_attempt_failed,
              source: self,
              session_id: @session_id,
              failure: failure
            )
          )
        end

        private

        def publish_connection_end(reason, failure, session_id)
          failure ||= connection_end_failure(reason)
          distribute_event(
            Event.new(
              type: :connection_ended,
              source: self,
              session_id: session_id,
              failure: failure,
              context: { reason: reason }
            )
          )
        end
      end
    end
  end
end
