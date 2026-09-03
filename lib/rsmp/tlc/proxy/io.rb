module RSMP
  module TLC
    module Proxy
      # Command methods for I/O control of a remote TLC.
      # Covers detector logic, input/output forcing and setting.
      module IO
        # M0006 - Set a single input to a given status.
        def set_input(input:, status:, within:)
          readiness = validate_ready 'set input'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0006',
            'cO' => 'setInput',
            'n' => 'status',
            'v' => command_value('M0006', 'status', status)
          }, {
            'cCI' => 'M0006',
            'cO' => 'setInput',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0006',
            'cO' => 'setInput',
            'n' => 'input',
            'v' => command_value('M0006', 'input', input)
          }]
          send_command_and_collect(command_list, within: within)
        end

        def set_input!(...)
          set_input(...).value!
        end

        # M0013 - Set all inputs via a bit-pattern string.
        def set_inputs(status, within:)
          readiness = validate_ready 'set inputs'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0013',
            'cO' => 'setInput',
            'n' => 'status',
            'v' => command_value('M0013', 'status', status)
          }, {
            'cCI' => 'M0013',
            'cO' => 'setInput',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_and_collect(command_list, within: within)
        end

        def set_inputs!(...)
          set_inputs(...).value!
        end

        # M0019 - Force an input to a given value.
        def force_input(input:, status:, value:, within:)
          readiness = validate_ready 'force input'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          command_list = force_input_command_list(input, status, value)
          confirm_status = force_input_confirm_status(input, status, value)
          send_command_and_collect(command_list, within: within).and_then do |exchange|
            wait_for_status("force input #{input}", confirm_status, timeout: within).map { exchange }
          end
        end

        def force_input!(...)
          force_input(...).value!
        end

        # M0020 - Force an output to a given value.
        def force_output(output:, status:, value:, within:)
          readiness = validate_ready 'force output'
          return readiness if readiness.failure?

          raise 'TLC main component not found' unless main

          send_command_and_collect(force_output_command_list(output, status, value), within: within)
        end

        def force_output!(...)
          force_output(...).value!
        end

        private

        def force_output_command_list(output, status, value)
          security_code = security_code_for(2)
          values = { 'status' => status, 'output' => output, 'outputValue' => value }
          values.map do |name, item|
            { 'cCI' => 'M0020', 'cO' => 'setOutput', 'n' => name, 'v' => command_value('M0020', name, item) }
          end.insert(1, {
                       'cCI' => 'M0020',
                       'cO' => 'setOutput',
                       'n' => 'securityCode',
                       'v' => security_code.to_s
                     })
        end

        def force_input_command_list(input, status, value)
          security_code = security_code_for(2)
          [
            { 'cCI' => 'M0019', 'cO' => 'setInput', 'n' => 'status',
              'v' => command_value('M0019', 'status', status) },
            { 'cCI' => 'M0019', 'cO' => 'setInput', 'n' => 'securityCode', 'v' => security_code.to_s },
            { 'cCI' => 'M0019', 'cO' => 'setInput', 'n' => 'input',
              'v' => command_value('M0019', 'input', input) },
            { 'cCI' => 'M0019', 'cO' => 'setInput', 'n' => 'inputValue',
              'v' => command_value('M0019', 'inputValue', value) }
          ]
        end

        def force_input_confirm_status(input, status, value)
          result = []
          # S0029 is used to check the forced status, but is only available from sxl 1.0.13
          if RSMP::Proxy.version_meets_requirement?(sxl_version, '>=1.0.13')
            result << { 'sCI' => 'S0029', 'n' => 'status',
                        's' => /^.{#{input.to_i - 1}}#{boolean_value(status) ? '1' : '0'}/ }
          end
          if boolean_value(status)
            result << { 'sCI' => 'S0003', 'n' => 'inputstatus',
                        's' => /^.{#{input.to_i - 1}}#{boolean_value(value) ? '1' : '0'}/ }
          end
          result
        end
      end
    end
  end
end
