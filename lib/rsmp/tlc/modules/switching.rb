# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # State switching and control mode methods
      module Switching
        def set_fixed_time_control(status, source:)
          @fixed_time_control = status
          @fixed_time_control_source = source
        end

        def switch_plan(plan, source:)
          plan_nr = plan.to_i
          if plan_nr.zero?
            log 'Switching to plan selection by time table', level: :info
          else
            find_plan plan_nr
            log "Switching to plan #{plan_nr}", level: :info
          end
          @plan = plan_nr
          @plan_source = source
        end

        def switch_functional_position(mode, source:, timeout: nil, reverting: false)
          unless %w[NormalControl YellowFlash Dark].include? mode
            raise RSMP::MessageRejected,
                  "Invalid functional position #{mode.inspect}, must be NormalControl, YellowFlash or Dark"
          end

          if reverting
            log "Reverting to functional position #{mode} after timeout", level: :info
          elsif timeout&.positive?
            log "Switching to functional position #{mode} with timeout #{(timeout / 60).round(1)}min", level: :info
            @previous_functional_position = @function_position
            now = clock.now
            @functional_position_timeout = now + timeout
          else
            log "Switching to functional position #{mode}", level: :info
          end
          initiate_startup_sequence if (mode == 'NormalControl') && (@function_position != 'NormalControl')
          @function_position = mode
          @function_position_source = source
          mode
        end
      end
    end
  end
end
