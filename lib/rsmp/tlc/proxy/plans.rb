module RSMP
  module TLC
    module Proxy
      # Command methods for signal plans.
      # Covers time plans, week/day tables, bands, offsets, and cycle times.
      module Plans
        # M0014 — Set dynamic bands for a signal plan.
        def set_dynamic_bands(plan:, status:, within:)
          validate_ready 'set dynamic bands'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0014',
            'cO' => 'setCommands',
            'n' => 'status',
            'v' => status.to_s
          }, {
            'cCI' => 'M0014',
            'cO' => 'setCommands',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0014',
            'cO' => 'setCommands',
            'n' => 'plan',
            'v' => plan.to_s
          }]
          send_command_and_collect(command_list, within: within).ok!
        end

        # M0023 — Set timeout for dynamic bands.
        def set_dynamic_bands_timeout(status, within:)
          validate_ready 'set dynamic bands timeout'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0023',
            'cO' => 'setTimeout',
            'n' => 'status',
            'v' => status.to_s
          }, {
            'cCI' => 'M0023',
            'cO' => 'setTimeout',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, within: within).ok!
        end

        # M0015 — Set offset for a signal plan.
        def set_offset(plan:, offset:, within:)
          validate_ready 'set offset'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0015',
            'cO' => 'setOffset',
            'n' => 'status',
            'v' => offset.to_s
          }, {
            'cCI' => 'M0015',
            'cO' => 'setOffset',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0015',
            'cO' => 'setOffset',
            'n' => 'plan',
            'v' => plan.to_s
          }]
          send_command_and_collect(command_list, within: within).ok!
        end

        # Set the timeplan (signal plan) on the remote TLC.
        def set_timeplan(plan_nr, within:)
          validate_ready 'set timeplan'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0002',
            'cO' => 'setPlan',
            'n' => 'status',
            'v' => 'True'
          }, {
            'cCI' => 'M0002',
            'cO' => 'setPlan',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0002',
            'cO' => 'setPlan',
            'n' => 'timeplan',
            'v' => plan_nr.to_s
          }]
          confirm_status = [{ 'sCI' => 'S0014', 'n' => 'status', 's' => plan_nr.to_s }]
          send_command_and_collect(command_list, within: within).ok!
          wait_for_status("timeplan #{plan_nr}", confirm_status, timeout: within)
        end

        # M0016 — Set week table (mapping week days to traffic situations).
        def set_week_table(status, within:)
          validate_ready 'set week table'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0016',
            'cO' => 'setWeekTable',
            'n' => 'status',
            'v' => status.to_s
          }, {
            'cCI' => 'M0016',
            'cO' => 'setWeekTable',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, within:).ok!
        end

        # M0017 — Set day table (mapping time periods to signal plans).
        def set_day_table(status, within:)
          validate_ready 'set day table'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0017',
            'cO' => 'setDayTable',
            'n' => 'status',
            'v' => status.to_s
          }, {
            'cCI' => 'M0017',
            'cO' => 'setDayTable',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, within:).ok!
        end

        # M0018 — Set cycle time for a signal plan.
        def set_cycle_time(plan:, cycle_time:, within:)
          validate_ready 'set cycle time'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0018',
            'cO' => 'setCycleTime',
            'n' => 'status',
            'v' => cycle_time.to_s
          }, {
            'cCI' => 'M0018',
            'cO' => 'setCycleTime',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0018',
            'cO' => 'setCycleTime',
            'n' => 'plan',
            'v' => plan.to_s
          }]
          send_command_and_collect(command_list, within:).ok!
        end

        # M0010 — Order signal start for a signal group component.
        def order_signal_start(component_id, within:)
          validate_ready 'order signal start'

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0010',
            'cO' => 'setStart',
            'n' => 'status',
            'v' => 'True'
          }, {
            'cCI' => 'M0010',
            'cO' => 'setStart',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, component: component_id, within:).ok!
        end

        # M0011 — Order signal stop for a signal group component.
        def order_signal_stop(component_id, within:)
          validate_ready 'order signal stop'

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0011',
            'cO' => 'setStop',
            'n' => 'status',
            'v' => 'True'
          }, {
            'cCI' => 'M0011',
            'cO' => 'setStop',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, component: component_id, within:).ok!
        end
      end
    end
  end
end
