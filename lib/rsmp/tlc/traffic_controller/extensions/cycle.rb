module RSMP
  module TLC
    module TrafficControllerExtensions
      module Cycle
        def timer(_now)
          return unless move_cycle_counter

          check_functional_position_timeout
          move_startup_sequence if @startup_sequence_active

          @signal_groups.each(&:timer)
          @signal_priorities.each(&:timer)

          output_states
        end

        def move_cycle_counter
          plan = current_plan
          counter = if plan
                      Time.now.to_i % plan.cycle_time
                    else
                      0
                    end
          changed = counter != @cycle_counter
          @cycle_counter = counter
          changed
        end

        def check_functional_position_timeout
          return unless @functional_position_timeout
          return unless clock.now >= @functional_position_timeout

          switch_functional_position @previous_functional_position, reverting: true, source: 'calendar_clock'
          @functional_position_timeout = nil
          @previous_functional_position = nil
        end

        def startup_state
          return unless @startup_sequence_active
          return unless @startup_sequence_pos

          @startup_sequence[@startup_sequence_pos]
        end

        def initiate_startup_sequence
          log 'Initiating startup sequence', level: :info
          reset_modes
          @startup_sequence_active = true
          @startup_sequence_initiated_at = nil
          @startup_sequence_pos = nil
        end

        def end_startup_sequence
          @startup_sequence_active = false
          @startup_sequence_initiated_at = nil
          @startup_sequence_pos = nil
        end

        def move_startup_sequence
          if @startup_sequence_initiated_at.nil?
            @startup_sequence_initiated_at = Time.now.to_i + 1
            @startup_sequence_pos = 0
          else
            @startup_sequence_pos = Time.now.to_i - @startup_sequence_initiated_at
          end
          return unless @startup_sequence_pos >= @startup_sequence.size

          end_startup_sequence
        end
      end
    end
  end
end
