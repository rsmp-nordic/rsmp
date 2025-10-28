module RSMP
  class Proxy
    module Modules
      # Reader and timer task management
      # Handles async tasks for reading from socket and running periodic timers
      module Tasks
        # run an async task that reads from @socket
        def start_reader
          @reader = @task.async do |task|
            task.annotate 'reader'
            run_reader
          end
        end

        def run_reader
          @stream ||= IO::Stream::Buffered.new(@socket)
          @protocol ||= RSMP::Protocol.new(@stream) # rsmp messages are json terminated with a form-feed
          loop do
            read_line
          end
        rescue Restart
          log 'Closing connection', level: :warning
          raise
        rescue EOFError, Async::Stop
          log 'Connection closed', level: :warning
        rescue IOError => e
          log "IOError: #{e}", level: :warning
        rescue Errno::ECONNRESET
          log 'Connection reset by peer', level: :warning
        rescue Errno::EPIPE
          log 'Broken pipe', level: :warning
        rescue StandardError => e
          distribute_error e, level: :internal
        end

        def read_line
          json = @protocol.read_line
          beginning = Time.now
          message = process_packet json
          duration = Time.now - beginning
          ms = (duration * 1000).round(4)
          per_second = if duration.positive?
                         (1.0 / duration).round
                       else
                         Float::INFINITY
                       end
          if message
            type = message.type
            m_id = Logger.shorten_message_id(message.m_id)
          else
            type = 'Unknown'
            m_id = nil
          end
          str = [type, m_id, "processed in #{ms}ms, #{per_second}req/s"].compact.join(' ')
          log str, level: :statistics
        end

        def start_timer
          return if @timer

          name = 'timer'
          interval = @site_settings['intervals']['timer'] || 1
          log "Starting #{name} with interval #{interval} seconds", level: :debug
          @latest_watchdog_received = Clock.now
          @timer = @task.async do |task|
            task.annotate 'timer'
            run_timer task, interval
          end
        end

        def run_timer(task, interval)
          next_time = Time.now.to_f
          loop do
            begin
              now = Clock.now
              timer(now)
            rescue RSMP::Schema::Error => e
              log "Timer: Schema error: #{e}", level: :warning
            rescue EOFError => e
              log "Timer: Connection closed: #{e}", level: :warning
            rescue IOError
              log 'Timer: IOError', level: :warning
            rescue Errno::ECONNRESET
              log 'Timer: Connection reset by peer', level: :warning
            rescue Errno::EPIPE
              log 'Timer: Broken pipe', level: :warning
            rescue StandardError => e
              distribute_error e, level: :internal
            end
          ensure
            next_time += interval
            duration = next_time - Time.now.to_f
            task.sleep duration
          end
        end

        def timer(now)
          watchdog_send_timer now
          check_ack_timeout now
          check_watchdog_timeout now
        end
      end
    end
  end
end
