# frozen_string_literal: true

module RSMP
  class Proxy
    module Modules
      # Watchdog functionality for monitoring connection health
      # Handles sending and receiving watchdog messages
      module Watchdog
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

        def check_watchdog_timeout(now)
          timeout = @site_settings['timeouts']['watchdog']
          latest = @latest_watchdog_received + timeout
          left = latest - now
          return unless left.negative?

          str = "No Watchdog received within #{timeout} seconds"
          log str, level: :warning
          distribute MissingWatchdog.new(str)
        end

        def process_watchdog(message)
          log "Received #{message.type}", message: message, level: :log
          @latest_watchdog_received = Clock.now
          acknowledge message
        end
      end
    end
  end
end
