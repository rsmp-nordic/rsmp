module RSMP
  module TLC
    module TrafficControllerExtensions
      module State
        def reset_modes
          @function_position = 'NormalControl'
          @function_position_source = 'startup'
          @previous_functional_position = nil
          @functional_position_timeout = nil

          @booting = false
          @is_starting = false
          @control_mode = 'control'
          @manual_control = false
          @manual_control_source = 'startup'
          @fixed_time_control = false
          @fixed_time_control_source = 'startup'
          @isolated_control = false
          @isolated_control_source = 'startup'
          @all_red = false
          @all_red_source = 'startup'
          @police_key = 0
        end

        def reset
          reset_modes
          @cycle_counter = 0
          @plan = 1
          @plan_source = 'startup'
          @intersection = 0
          @intersection_source = 'startup'
          @emergency_routes = Set.new
          @last_emergency_route = nil
          @traffic_situation = 0
          @traffic_situation_source = 'startup'
          @day_time_table = {}
          @startup_sequence_active = false
          @startup_sequence_initiated_at = nil
          @startup_sequence_pos = 0
          @time_int = nil
          @inputs.reset
          @signal_priorities = []
          @dynamic_bands_timeout = 0
        end

        def dark?
          @function_position == 'Dark'
        end

        def yellow_flash?
          @function_position == 'YellowFlash'
        end

        def normal_control?
          @function_position == 'NormalControl'
        end

        def clock
          node.clock
        end

        def current_plan
          return unless @plans

          @plans[plan] || @plans.values.first
        end

        def add_signal_group(group)
          @signal_groups << group
        end

        def add_detector_logic(logic)
          @detector_logics << logic
        end

        def signal_priority_changed(priority, state); end

        def prune_priorities
          @signal_priorities.delete_if(&:prune?)
        end

        def status_updates_sent
          prune_priorities
        end

        def priority_list
          @signal_priorities.map do |priority|
            {
              'r' => priority.id,
              't' => RSMP::Clock.to_s(priority.updated),
              's' => priority.state
            }
          end
        end
      end
    end
  end
end
