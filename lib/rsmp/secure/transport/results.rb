module RSMP
  module Secure
    class Transport
      # Tracks command result mailboxes and propagates transport failures.
      module Results
        private

        def enqueue_command(command)
          raise @error if @error

          register_result(command.result)
          @commands.enqueue(command)
        rescue Async::Queue::ClosedError
          unregister_result(command.result)
          raise @error if @error

          raise IOError, 'Secure RSMP transport is closed'
        end

        def write_frame(frame)
          raise @error if @error

          result = result_queue
          register_result(result)
          @writes.enqueue(WriteRequest.new(frame: frame, result: result))
          wait_result(result)
        rescue Async::Queue::ClosedError
          unregister_result(result)
          raise @error if @error

          raise IOError, 'Secure RSMP transport is closed'
        end

        def result_queue
          Async::Queue.new
        end

        def wait_result(result)
          status, value = result.dequeue
          unregister_result(result)
          raise value if status == :error
          raise @error if @error && status != :ok
          raise IOError, 'Secure RSMP transport is closed' unless status == :ok

          value
        end

        def complete_result(result, value = nil, error: nil)
          unregister_result(result)
          if error
            result.enqueue([:error, error])
          else
            result.enqueue([:ok, value])
          end
        rescue Async::Queue::ClosedError
          nil
        end

        def register_result(result)
          @pending_results << result
        end

        def unregister_result(result)
          @pending_results.delete(result)
        end

        def fail_transport(error)
          return if @error

          @error = error
          pending = @pending_results.dup
          pending.each { |result| complete_result(result, error: error) }
          @inbound.close unless @inbound.closed?
          @commands.close unless @commands.closed?
          @writes.close unless @writes.closed?
          @rekey_responses.close unless @rekey_responses.closed?
          @rekey_done.signal
        end

        def raise_if_failed
          raise @error if @error
        end

        def secure_transport_error?(error)
          error.is_a?(FrameError) ||
            error.is_a?(AuthenticationError) ||
            error.is_a?(ReplayError) ||
            error.is_a?(HandshakeError) ||
            error.is_a?(IOError) ||
            error.is_a?(SystemCallError)
        end
      end
    end
  end
end
