module RSMP
  class Proxy
    module Modules
      # Reader and timer tasks are siblings in one supervised session barrier.
      module Tasks
        def session_active?(id = @session_id)
          id == @session_id && !@session_closed
        end

        def session_tasks
          @session_tasks ||= Async::Barrier.new(parent: @task)
        end

        def start_reader
          id = @session_id
          @reader = session_tasks.async do |task|
            task.annotate "reader session #{id}"
            run_reader(id)
          end
        end

        def run_reader(id)
          @stream ||= IO::Stream::Buffered.new(@socket)
          @protocol ||= RSMP::Protocol.new(@stream)
          while session_active?(id)
            line = read_protocol_line
            return line if line.failure?

            process_received_line(line.value)
          end
          Result.success(:closed)
        end

        def read_protocol_line
          json = @protocol.read_line
          raise EOFError, 'Connection closed by peer' unless json

          Result.success(json)
        rescue EOFError => e
          connection_read_failure(:peer_closed, 'Connection closed by peer', e)
        rescue IOError, Errno::ECONNRESET, Errno::EPIPE => e
          connection_read_failure(:transport_failure, e.message, e)
        end

        def connection_read_failure(reason, text, error)
          log(text, level: :warning)
          Result.failure(
            :disconnected,
            message: text,
            source: reason == :peer_closed ? :peer : :transport,
            context: { reason: reason, session_id: @session_id },
            cause: error
          )
        end

        # Wait for the reader while observing every sibling. A failed timer task
        # raises here with its original exception and backtrace.
        def wait_for_session
          reader = @reader
          observed = session_tasks.wait do |finished|
            result = finished.wait
            break result if finished.equal?(reader)
            next if finished.cancelled? || !session_active?

            raise "#{finished.annotation} ended while its connection session was active"
          end
          observed.is_a?(Result::Success) || observed.is_a?(Result::Failure) ? observed : Result.success(:closed)
        ensure
          @session_tasks.cancel if @session_tasks && !@session_tasks.empty?
          @session_tasks = nil
        end

        def process_received_line(json)
          beginning = Time.now
          result = process_packet(json)
          log_processing_statistics(result, beginning)
          result
        end

        def log_processing_statistics(result, beginning)
          message = result.success? ? result.value : result.failure.context[:message]
          duration = Time.now - beginning
          type = message.respond_to?(:type) ? message.type : 'Unknown'
          m_id = message.respond_to?(:m_id) ? Logger.shorten_message_id(message.m_id) : nil
          log([type, m_id, processing_speed(duration)].compact.join(' '), level: :statistics)
        end

        def processing_speed(duration)
          milliseconds = (duration * 1000).round(4)
          per_second = duration.positive? ? (1.0 / duration).round : Float::INFINITY
          "processed in #{milliseconds}ms, #{per_second}req/s"
        end

        def start_timer
          return if @timer&.running?

          id = @session_id
          interval = @site_settings['intervals']['timer'] || 1
          log "Starting timer with interval #{interval} seconds", level: :debug
          @latest_watchdog_received = Clock.now
          @timer = session_tasks.async do |task|
            task.annotate "timer session #{id}"
            run_timer(task, interval, id)
          end
        end

        def run_timer(task, interval, id)
          next_time = Time.now.to_f
          while session_active?(id)
            timer(Clock.now)
            next_time += interval
            task.sleep([next_time - Time.now.to_f, 0].max) if session_active?(id)
          end
          Result.success(:closed)
        end

        def timer(now)
          watchdog_send_timer(now)
          check_ack_timeout(now)
          check_watchdog_timeout(now)
        end
      end
    end
  end
end
