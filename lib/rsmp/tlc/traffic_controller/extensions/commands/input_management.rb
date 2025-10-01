module RSMP
  module TLC
    module TrafficControllerExtensions
      module Commands
        module InputManagement
          def handle_m0006(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            input = arg['input'].to_i
            status = string_to_bool arg['status']
            raise MessageRejected, "Input must be in the range 1-#{@inputs.size}" unless input.between?(1, @inputs.size)

            log "#{status ? 'Activating' : 'Deactivating'} input #{input}", level: :info
            change = @inputs.set input, status
            input_logic input, change unless change.nil?
          end

          def handle_m0013(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            set, clear = parse_input_status(arg['status'])
            validate_input_ranges(set, clear)
            apply_input_changes(set, clear)
          end

          def handle_m0019(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            input = arg['input'].to_i
            force = string_to_bool arg['status']
            forced_value = string_to_bool arg['inputValue']
            raise MessageRejected, "Input must be in the range 1-#{@inputs.size}" unless input.between?(1, @inputs.size)

            log "#{force ? 'Forcing' : 'Releasing'} input #{input}", level: :info
            change = @inputs.set_forcing input, force: force, forced_value: forced_value

            input_logic input, change unless change.nil?
          end

          def string_to_bool(bool_str)
            case bool_str
            when 'True'
              true
            when 'False'
              false
            else
              raise RSMP::MessageRejected, "Invalid boolean '#{bool_str}', must be 'True' or 'False'"
            end
          end

          def bool_string_to_digit(bool)
            case bool
            when 'True'
              '1'
            when 'False'
              '0'
            else
              raise RSMP::MessageRejected, "Invalid boolean '#{bool}', must be 'True' or 'False'"
            end
          end

          def bool_to_digit(bool)
            bool ? '1' : '0'
          end

          private

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
            set -= (set & clear)

            [set, clear]
          end

          def extract_input_bits(bits, offset, target_array)
            bits.to_s(2).reverse.each_char.with_index do |bit, i|
              target_array << (i + offset) if bit == '1'
            end
          end

          def validate_input_ranges(set, clear)
            [set, clear].each do |inputs|
              inputs.each do |input|
                if input < 1
                  raise MessageRejected,
                        invalid_input_range_message(set, clear, input, 'must be 1 or higher')
                end
                next unless input > @inputs.size

                detail = "only #{@inputs.size} inputs present"
                raise MessageRejected, invalid_input_range_message(set, clear, input, detail)
              end
            end
          end

          def invalid_input_range_message(set, clear, input, detail)
            "Cannot activate inputs #{set} and deactivate inputs #{clear}: input #{input} is invalid (#{detail})"
          end

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
        end
      end
    end
  end
end
