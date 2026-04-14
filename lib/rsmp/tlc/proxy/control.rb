module RSMP
  module TLC
    module Proxy
      # Command methods for operational control of a remote TLC.
      # Covers functional position, emergency routes, I/O modes, signal group orders, and system settings.
      module Control
        # M0001 — Set functional position (NormalControl, YellowFlash, Dark).
        def set_functional_position(status, timeout_minutes: 0, within: nil)
          validate_ready 'set functional position'
          raise 'TLC main component not found' unless main

          command_list = functional_position_command_list(status, timeout_minutes)
          confirm_status = functional_position_confirm_status(status)
          send_command_with_confirm main.c_id, command_list, "functional position #{status}", confirm_status, within: within
        end

        # M0005 — Set or clear an emergency route.
        def set_emergency_route(route:, active:, within: nil)
          validate_ready 'set emergency route'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)
          active_str = active ? 'True' : 'False'

          command_list = [{
            'cCI' => 'M0005',
            'cO' => 'setEmergency',
            'n' => 'status',
            'v' => active_str
          }, {
            'cCI' => 'M0005',
            'cO' => 'setEmergency',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0005',
            'cO' => 'setEmergency',
            'n' => 'emergencyroute',
            'v' => route.to_s
          }]

          confirm_status = [{ 'sCI' => 'S0006', 'n' => 'status', 's' => active_str }]
          send_command_with_confirm main.c_id, command_list, "emergency route #{route} #{active ? 'active' : 'inactive'}", confirm_status, within: within
        end

        # M0007 — Enable or disable fixed-time control.
        def set_fixed_time(status, within: nil)
          validate_ready 'set fixed time'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0007',
            'cO' => 'setFixedTime',
            'n' => 'status',
            'v' => status.to_s
          }, {
            'cCI' => 'M0007',
            'cO' => 'setFixedTime',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]

          confirm_status = [{ 'sCI' => 'S0009', 'n' => 'status',
                              's' => /^#{Regexp.escape(status.to_s)}(,#{Regexp.escape(status.to_s)})*$/ }]
          send_command_with_confirm main.c_id, command_list, "fixed time #{status}", confirm_status, within: within
        end

        # M0003 — Set traffic situation (activate a specific situation number).
        def set_traffic_situation(situation, within: nil)
          validate_ready 'set traffic situation'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0003',
            'cO' => 'setTrafficSituation',
            'n' => 'status',
            'v' => 'True'
          }, {
            'cCI' => 'M0003',
            'cO' => 'setTrafficSituation',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0003',
            'cO' => 'setTrafficSituation',
            'n' => 'traficsituation',
            'v' => situation.to_s
          }]

          confirm_status = [{ 'sCI' => 'S0015', 'n' => 'status', 's' => situation.to_s }]
          send_command_with_confirm main.c_id, command_list, "traffic situation #{situation}", confirm_status, within: within
        end

        # M0003 — Clear the active traffic situation.
        def unset_traffic_situation(options: {}, within: nil)
          validate_ready 'unset traffic situation'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0003',
            'cO' => 'setTrafficSituation',
            'n' => 'status',
            'v' => 'False'
          }, {
            'cCI' => 'M0003',
            'cO' => 'setTrafficSituation',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0003',
            'cO' => 'setTrafficSituation',
            'n' => 'traficsituation',
            'v' => '1'
          }]

          confirm_status = [{ 'sCI' => 'S0015', 'n' => 'status', 's' => '1' }]
          send_command_with_confirm main.c_id, command_list, 'traffic situation unset', confirm_status, within: within
        end

        private

        def functional_position_command_list(status, timeout_minutes)
          security_code = security_code_for(2)
          [
            { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'status', 'v' => status.to_s },
            { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'securityCode', 'v' => security_code.to_s },
            { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'timeout', 'v' => timeout_minutes.to_s },
            { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'intersection', 'v' => '0' }
          ]
        end

        def functional_position_confirm_status(status)
          case status.to_s
          when 'YellowFlash'
            [{ 'sCI' => 'S0011', 'n' => 'status', 's' => /^True(,True)*$/ }]
          when 'Dark'
            [{ 'sCI' => 'S0007', 'n' => 'status', 's' => /^False(,False)*$/ }]
          when 'NormalControl'
            [
              { 'sCI' => 'S0007', 'n' => 'status', 's' => /^True(,True)*$/ },
              { 'sCI' => 'S0011', 'n' => 'status', 's' => /^False(,False)*$/ },
              { 'sCI' => 'S0005', 'n' => 'status', 's' => 'False' }
            ]
          else
            []
          end
        end
      end
    end
  end
end
