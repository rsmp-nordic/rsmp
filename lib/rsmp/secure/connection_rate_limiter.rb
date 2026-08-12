module RSMP
  module Secure
    # Bounds repeated expensive secure handshakes from one remote peer.
    class ConnectionRateLimiter
      MAX_FAILURES = 5
      WINDOW_SECONDS = 60
      BLOCK_SECONDS = 30

      Entry = Struct.new(:failures, :blocked_until, keyword_init: true)

      def initialize(max_failures: MAX_FAILURES, window: WINDOW_SECONDS, block: BLOCK_SECONDS, clock: nil)
        @max_failures = Integer(max_failures)
        @window = Float(window)
        @block = Float(block)
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @entries = {}
        @mutex = Mutex.new
      end

      def check!(key)
        key = normalize_key(key)
        now = @clock.call
        blocked = @mutex.synchronize do
          entry = active_entry(key, now)
          entry&.blocked_until && entry.blocked_until > now
        end
        raise RateLimitError, 'Repeated failed secure connections are temporarily rate limited' if blocked
      end

      def record_failure(key)
        key = normalize_key(key)
        now = @clock.call
        @mutex.synchronize do
          entry = active_entry(key, now) || Entry.new(failures: [], blocked_until: nil)
          entry.failures << now
          entry.blocked_until = now + @block if entry.failures.size >= @max_failures
          @entries[key] = entry
        end
      end

      private

      def active_entry(key, now)
        entry = @entries[key]
        return unless entry

        entry.failures.reject! { |failure| failure <= now - @window }
        if entry.failures.empty? && (!entry.blocked_until || entry.blocked_until <= now)
          @entries.delete(key)
          return
        end
        entry
      end

      def normalize_key(key)
        value = key.to_s
        raise ArgumentError, 'Secure connection rate-limit key must not be empty' if value.empty?

        value
      end
    end
  end
end
