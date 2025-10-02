# frozen_string_literal: true

module RSMP
  module TLC
    # Input programming, control, and status for traffic controllers
    # Handles input commands and queries
    module InputCommands
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

      # S0091 - User login status
      def handle_s0091(_status_code, status_name = nil, options = {})
        if Proxy.version_meets_requirement? options[:sxl_version], '>=1.1'
          case status_name
          when 'user'
            TrafficControllerSite.make_status 0
          end
        else
          case status_name
          when 'user'
            TrafficControllerSite.make_status 'nobody'
          when 'status'
            TrafficControllerSite.make_status 'logout'
          end
        end
      end

      # S0092 - User login sensitivity
      def handle_s0092(_status_code, status_name = nil, options = {})
        if Proxy.version_meets_requirement? options[:sxl_version], '>=1.1'
          case status_name
          when 'user'
            TrafficControllerSite.make_status 0
          end
        else
          case status_name
          when 'user'
            TrafficControllerSite.make_status 'nobody'
          when 'status'
            TrafficControllerSite.make_status 'logout'
          end
        end
      end

      # S0205 - Start of signal group green
      def handle_s0205(_status_code, status_name = nil, _options = {})
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'vehicles'
          TrafficControllerSite.make_status 0
        end
      end

      # S0206 - Expected end of signal group green
      def handle_s0206(_status_code, status_name = nil, _options = {})
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'speed'
          TrafficControllerSite.make_status 0
        end
      end

      # S0207 - Predicted time to green
      def handle_s0207(_status_code, status_name = nil, _options = {})
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'occupancy'
          values = [-1, 0, 50, 100]
          output = @detector_logics.each_with_index.map { |_dl, i| values[i % values.size] }.join(',')
          TrafficControllerSite.make_status output
        end
      end

      # S0208 - Predicted time to red
      def handle_s0208(_status_code, status_name = nil, _options = {})
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'P', 'PS', 'L', 'LS', 'B', 'SP', 'MC', 'C', 'F'
          TrafficControllerSite.make_status 0
        end
      end
    end
  end
end
