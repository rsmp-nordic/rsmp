module RSMP
  module Secure
    class Transport
      module Rekey
        # Mandatory per-direction frame, byte, and time renewal policy.
        module Policy
          private

          def rekey_due?
            message_rekey_due? || byte_rekey_due? || time_rekey_due?
          end

          def message_rekey_due?
            threshold = [@settings['rekey_after_messages'] - REKEY_FRAME_RESERVE, 1].max
            @channel.sent_frames >= threshold || @channel.received_frames >= threshold
          end

          def byte_rekey_due?
            reserve = REKEY_FRAME_RESERVE * @settings['max_frame_size']
            threshold = [@settings['rekey_after_bytes'] - reserve, 1].max
            @channel.sent_ciphertext_bytes >= threshold || @channel.received_ciphertext_bytes >= threshold
          end

          def time_rekey_due?
            threshold = [@settings['rekey_after_seconds'] - @settings['rekey_timeout'], 0].max
            (monotonic_now - @epoch_started_at) >= threshold
          end

          def rekey_error_within_limits?(attributes)
            return false if @channel.sent_frames >= @settings['rekey_after_messages']
            return false if time_limit_reached?

            ciphertext_bytes = Cbor.encode(attributes).bytesize + Channel::TAG_BYTES
            (@channel.sent_ciphertext_bytes + ciphertext_bytes) <= @settings['rekey_after_bytes']
          end

          def time_limit_reached?
            (monotonic_now - @epoch_started_at) >= @settings['rekey_after_seconds']
          end

          def install_channel(channel)
            previous = @channel
            @channel = channel
            @epoch_started_at = monotonic_now
            @epoch_changed.signal
            previous.clear! unless previous.equal?(channel)
            log_secure_channel_up
          end

          def run_rekey_monitor
            loop do
              deadline = @epoch_started_at + @settings['rekey_after_seconds'] - @settings['rekey_timeout']
              remaining = deadline - monotonic_now
              if remaining.positive?
                begin
                  Async::Task.current.with_timeout(remaining) { @epoch_changed.wait }
                  next
                rescue Async::TimeoutError
                  nil
                end
              end
              schedule_rekey_if_due
              @epoch_changed.wait
            end
          rescue Async::Queue::ClosedError, IOError
            nil
          rescue StandardError => e
            fail_transport(e)
          end
        end
      end
    end
  end
end
