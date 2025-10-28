module RSMP
  module TLC
    module Modules
      # Input programming, control, and status for traffic controllers
      # Handles input commands and queries
      module Inputs
        def setup_inputs(inputs)
          if inputs
            num_inputs = inputs['total']
            @input_programming = inputs['programming']
          else
            @input_programming = nil
          end
          @inputs = TLC::InputStates.new num_inputs || 8
        end

        def input_logic(input, change)
          return unless @input_programming && !change.nil?

          action = @input_programming[input]
          return unless action

          return unless action['raise_alarm']

          component = if action['component']
                        node.find_component action['component']
                      else
                        node.main
                      end
          alarm_code = action['raise_alarm']
          if change
            log "Activating input #{input} is programmed to raise alarm #{alarm_code} on #{component.c_id}",
                level: :info
            component.activate_alarm alarm_code
          else
            log "Deactivating input #{input} is programmed to clear alarm #{alarm_code} on #{component.c_id}",
                level: :info
            component.deactivate_alarm alarm_code
          end
        end

        # M0006 - Set input
        def handle_m0006(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          input = arg['input'].to_i
          status = string_to_bool arg['status']
          raise MessageRejected, "Input must be in the range 1-#{@inputs.size}" unless input.between?(1, @inputs.size)

          if status
            log "Activating input #{input}", level: :info
          else
            log "Deactivating input #{input}", level: :info
          end
          change = @inputs.set input, status
          input_logic input, change unless change.nil?
        end

        # M0012 - Set input (simple)
        def handle_m0012(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
        end

        # M0013 - Set input (complex bit pattern)
        def handle_m0013(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          set, clear = parse_input_status(arg['status'])
          validate_input_ranges(set, clear)
          apply_input_changes(set, clear)
        end

        # Helper: Parse input status string into set and clear arrays
        def parse_input_status(status_string)
          set = []
          clear = []
          status_string.split(';').each do |part|
            offset, set_bits, clear_bits = part.split(',').map(&:to_i)
            extract_input_bits(set_bits, offset, set)
            extract_input_bits(clear_bits, offset, clear)
          end

          set = set.uniq.sort
          clear = clear.uniq.sort
          # if input is both activated and deactivated, there is no need to activate first
          set -= (set & clear)

          [set, clear]
        end

        # Helper: Extract individual input bits from a bit pattern
        def extract_input_bits(bits, offset, target_array)
          bits.to_s(2).reverse.each_char.with_index do |bit, i|
            target_array << (i + offset) if bit == '1'
          end
        end

        # Helper: Validate that input indices are in valid range
        def validate_input_ranges(set, clear)
          [set, clear].each do |inputs|
            inputs.each do |input|
              if input < 1
                raise MessageRejected,
                      "Cannot activate inputs #{set} and deactivate inputs #{clear}: " \
                      "input #{input} is invalid (must be 1 or higher)"
              end
              next unless input > @inputs.size

              raise MessageRejected,
                    "Cannot activate inputs #{set} and deactivate inputs #{clear}: " \
                    "input #{input} is invalid (only #{@inputs.size} inputs present)"
            end
          end
        end

        # Helper: Apply input changes (activate/deactivate)
        def apply_input_changes(set, clear)
          log "Activating inputs #{set} and deactivating inputs #{clear}", level: :info

          set.each do |input|
            change = @inputs.set input, true
            input_logic input, change unless change.nil?
          end
          clear.each do |input|
            change = @inputs.set input, false
            input_logic input, change unless change.nil?
          end
        end

        # Helper: Set a specific input value
        def set_input(input_index, _value)
          return unless input_index >= 0 && input_index < @num_inputs

          @inputs[input_index] = bool_to_digit arg['value']
        end

        # M0019 - Force input
        def handle_m0019(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          input = arg['input'].to_i
          force = string_to_bool arg['status']
          forced_value = string_to_bool arg['inputValue']
          raise MessageRejected, "Input must be in the range 1-#{@inputs.size}" unless input.between?(1, @inputs.size)

          if force
            log "Forcing input #{input} to #{forced_value}", level: :info
          else
            log "Releasing input #{input}", level: :info
          end
          change = @inputs.set_forcing input, force: force, forced_value: forced_value

          input_logic input, change unless change.nil?
        end

        # S0003 - Input status
        def handle_s0003(_status_code, status_name = nil, _options = {})
          case status_name
          when 'inputstatus'
            TrafficControllerSite.make_status @inputs.actual_string
          when 'extendedinputstatus'
            TrafficControllerSite.make_status 0.to_s
          end
        end

        # S0029 - Forced input status
        def handle_s0029(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status @inputs.forced_string
          end
        end
      end
    end
  end
end
