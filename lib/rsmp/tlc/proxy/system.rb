module RSMP
  module TLC
    module Proxy
      # Command methods for operational control of a remote TLC.
      # Covers functional position, emergency routes, I/O modes, signal group orders, and system settings.
      module System
        # M0103 — Change security code for a given level.
        # Does not use security_code_for since the codes are passed explicitly.
        def set_security_code(level:, old_code:, new_code:, within: nil)
          validate_ready 'set security code'
          raise 'TLC main component not found' unless main

          command_list = [{
            'cCI' => 'M0103',
            'cO' => 'setSecurityCode',
            'n' => 'status',
            'v' => level.to_s
          }, {
            'cCI' => 'M0103',
            'cO' => 'setSecurityCode',
            'n' => 'oldSecurityCode',
            'v' => old_code.to_s
          }, {
            'cCI' => 'M0103',
            'cO' => 'setSecurityCode',
            'n' => 'newSecurityCode',
            'v' => new_code.to_s
          }]
          send_command_with_confirm main.c_id, command_list, "security code level #{level}", nil, within: within
        end

        # M0104 — Set the clock on the remote TLC. clock must respond to year/month/day/hour/min/sec.
        def set_clock(clock, within: nil)
          validate_ready 'set clock'
          raise 'TLC main component not found' unless main
          send_command_with_confirm main.c_id, clock_command_list(clock), 'clock', nil, within: within
        end

        private

        def clock_command_list(clock)
          security_code = security_code_for(1)
          [
            { 'cCI' => 'M0104', 'cO' => 'setDate', 'n' => 'securityCode', 'v' => security_code.to_s },
            { 'cCI' => 'M0104', 'cO' => 'setDate', 'n' => 'year', 'v' => clock.year.to_s },
            { 'cCI' => 'M0104', 'cO' => 'setDate', 'n' => 'month', 'v' => clock.month.to_s },
            { 'cCI' => 'M0104', 'cO' => 'setDate', 'n' => 'day', 'v' => clock.day.to_s },
            { 'cCI' => 'M0104', 'cO' => 'setDate', 'n' => 'hour', 'v' => clock.hour.to_s },
            { 'cCI' => 'M0104', 'cO' => 'setDate', 'n' => 'minute', 'v' => clock.min.to_s },
            { 'cCI' => 'M0104', 'cO' => 'setDate', 'n' => 'second', 'v' => clock.sec.to_s }
          ]
        end
      end
    end
  end
end
