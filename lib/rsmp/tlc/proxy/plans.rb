module RSMP
  module TLC
    module Proxy
      # Command methods for signal plans.
      # Covers time plans, week/day tables, bands, offsets, and cycle times.
      module Plans
        # M0014 - Set dynamic bands for a signal plan.
        def set_dynamic_bands(plan:, status:, within:)
          readiness = validate_ready 'set dynamic bands'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0014',
            'cO' => 'setCommands',
            'n' => 'status',
            'v' => command_value('M0014', 'status', status)
          }, {
            'cCI' => 'M0014',
            'cO' => 'setCommands',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0014',
            'cO' => 'setCommands',
            'n' => 'plan',
            'v' => command_value('M0014', 'plan', plan)
          }]
          send_command_and_collect(command_list, within: within)
        end

        # M0023 - Set timeout for dynamic bands.
        def set_dynamic_bands_timeout(status, within:)
          readiness = validate_ready 'set dynamic bands timeout'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0023',
            'cO' => 'setTimeout',
            'n' => 'status',
            'v' => command_value('M0023', 'status', status)
          }, {
            'cCI' => 'M0023',
            'cO' => 'setTimeout',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, within: within)
        end

        # M0015 - Set offset for a signal plan.
        def set_offset(plan:, offset:, within:)
          readiness = validate_ready 'set offset'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0015',
            'cO' => 'setOffset',
            'n' => 'status',
            'v' => command_value('M0015', 'status', offset)
          }, {
            'cCI' => 'M0015',
            'cO' => 'setOffset',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0015',
            'cO' => 'setOffset',
            'n' => 'plan',
            'v' => command_value('M0015', 'plan', plan)
          }]
          send_command_and_collect(command_list, within: within)
        end

        # Set the timeplan (signal plan) on the remote TLC.
        def set_timeplan(plan_nr, within:)
          readiness = validate_ready 'set timeplan'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0002',
            'cO' => 'setPlan',
            'n' => 'status',
            'v' => command_value('M0002', 'status', true)
          }, {
            'cCI' => 'M0002',
            'cO' => 'setPlan',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0002',
            'cO' => 'setPlan',
            'n' => 'timeplan',
            'v' => command_value('M0002', 'timeplan', plan_nr)
          }]
          confirm_status = [{ 'sCI' => 'S0014', 'n' => 'status', 's' => integer_value(plan_nr) }]
          send_command_and_collect(command_list, within: within).and_then do |exchange|
            wait_for_status("timeplan #{plan_nr}", confirm_status, timeout: within).map { exchange }
          end
        end

        # M0016 - Set week table (mapping week days to traffic situations).
        def set_week_table(status, within:)
          readiness = validate_ready 'set week table'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0016',
            'cO' => 'setWeekTable',
            'n' => 'status',
            'v' => command_value('M0016', 'status', status)
          }, {
            'cCI' => 'M0016',
            'cO' => 'setWeekTable',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, within:)
        end

        # M0017 - Set day table (mapping time periods to signal plans).
        def set_day_table(status, within:)
          readiness = validate_ready 'set day table'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0017',
            'cO' => 'setTimeTable',
            'n' => 'status',
            'v' => command_value('M0017', 'status', status)
          }, {
            'cCI' => 'M0017',
            'cO' => 'setTimeTable',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, within:)
        end

        # M0018 - Set cycle time for a signal plan.
        def set_cycle_time(plan:, cycle_time:, within:)
          readiness = validate_ready 'set cycle time'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0018',
            'cO' => 'setCycleTime',
            'n' => 'status',
            'v' => command_value('M0018', 'status', cycle_time)
          }, {
            'cCI' => 'M0018',
            'cO' => 'setCycleTime',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0018',
            'cO' => 'setCycleTime',
            'n' => 'plan',
            'v' => command_value('M0018', 'plan', plan)
          }]
          send_command_and_collect(command_list, within:)
        end

        # M0010 - Order signal start for a signal group component.
        def order_signal_start(component_id, within:)
          readiness = validate_ready 'order signal start'
          return readiness if readiness.failure?

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0010',
            'cO' => 'setStart',
            'n' => 'status',
            'v' => command_value('M0010', 'status', true)
          }, {
            'cCI' => 'M0010',
            'cO' => 'setStart',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, component: component_id, within:)
        end

        # M0011 - Order signal stop for a signal group component.
        def order_signal_stop(component_id, within:)
          readiness = validate_ready 'order signal stop'
          return readiness if readiness.failure?

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0011',
            'cO' => 'setStop',
            'n' => 'status',
            'v' => command_value('M0011', 'status', true)
          }, {
            'cCI' => 'M0011',
            'cO' => 'setStop',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, component: component_id, within:)
        end
      end
    end
  end
end
