module RSMP
  module ProxyExtensions
    module Watchdog
      def receive_error(error, options = {})
        @node.receive_error error, options
      end

      def start_watchdog
        log "Starting watchdog with interval #{@site_settings['intervals']['watchdog']} seconds", level: :debug
        @watchdog_started = true
      end

      def stop_watchdog
        log 'Stopping watchdog', level: :debug
        @watchdog_started = false
      end

      def with_watchdog_disabled
        was = @watchdog_started
        stop_watchdog if was
        yield
      ensure
        start_watchdog if was
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

      def watchdog_send_timer(now)
        return unless @watchdog_started
        return if @site_settings['intervals']['watchdog'] == :never

        if @latest_watchdog_send_at.nil?
          send_watchdog now
        else
          # we add half the timer interval to pick the timer
          # event closes to the wanted wathcdog interval
          diff = now - @latest_watchdog_send_at
          if (diff + (0.5 * @site_settings['intervals']['timer'])) >= @site_settings['intervals']['watchdog']
            send_watchdog now
          end
        end
      end

      def send_watchdog(now = Clock.now)
        message = RSMP::Watchdog.new({ 'wTs' => clock.to_s })
        send_message message
        @latest_watchdog_send_at = now
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

      def check_watchdog_timeout(now)
        timeout = @site_settings['timeouts']['watchdog']
        latest = @latest_watchdog_received + timeout
        left = latest - now
        return unless left.negative?

        str = "No Watchdog received within #{timeout} seconds"
        log str, level: :warning
        distribute MissingWatchdog.new(str)
      end
    end
  end
end
