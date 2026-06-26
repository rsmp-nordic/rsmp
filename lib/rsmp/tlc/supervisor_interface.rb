module RSMP
  # Traffic Light Controller SXL support.
  module TLC
    # Supervisor-side TLC SXL interface.
    class SupervisorInterface < RSMP::SXL::SupervisorInterface
      include Proxy::Control
      include Proxy::IO
      include Proxy::Plans
      include Proxy::Status
      include Proxy::Detectors
      include Proxy::System

      attr_reader :timeplan_source, :timeplan, :timeouts,
                  :functional_position, :yellow_flash, :traffic_situation

      def initialize(...)
        super
        @timeplan_source = nil
        @timeplan = nil
        @functional_position = nil
        @yellow_flash = nil
        @traffic_situation = nil
        @timeouts = node.supervisor_settings.dig('default', 'timeouts') || {}
      end

      def current_plan
        @timeplan
      end

      def plan_source
        @timeplan_source
      end

      def subscribe_to_timeplan
        validate_ready 'subscribe to timeplan'

        status_list = [
          { 'sCI' => 'S0014', 'n' => 'status', 'uRt' => '0' },
          { 'sCI' => 'S0014', 'n' => 'source', 'uRt' => '0' }
        ]
        status_list.each { |item| item['sOc'] = true } if use_soc?

        raise 'TLC main component not found' unless main

        subscribe_to_status status_list, component: main.c_id
      end

      def process_status_update(message)
        status_values = message.attribute('sS')
        return unless status_values

        status_values.each { |item| cache_status_item(item) }
      end

      def process_message(message)
        process_status_update message if message.is_a?(RSMP::StatusUpdate)
      end

      def timeplan_attributes
        main&.statuses&.dig('S0014') || {}
      end

      private

      def auto_subscribe_to_statuses
        return unless main

        subscribe_to_timeplan
        subscribe_to_key_statuses
      end

      def security_code_for(level)
        codes = proxy.site_settings&.dig('security_codes') || {}
        code = codes[level] || codes[level.to_s]
        raise ArgumentError, "Security code for level #{level} is not configured" unless code

        code
      end

      def boolean_value(value)
        case value
        when true, 'True'
          true
        when false, 'False'
          false
        else
          value
        end
      end

      def integer_value(value)
        return value.to_i if value.is_a?(String) && value.match?(/\A[+-]?\d+\z/)

        value
      end

      def list_value(value)
        value.is_a?(Array) ? value : value.to_s.split(',')
      end

      def command_value(command_code, argument_name, value)
        descriptor = RSMP::Schema.sxl_argument_descriptor(name, sxl_version, :commands, command_code, argument_name)
        normalize_command_value(value, descriptor)
      end

      def normalize_command_value(value, descriptor)
        type = descriptor.is_a?(Hash) ? descriptor['type'] : descriptor.to_s
        case type
        when 'boolean', 'boolean_as_string'
          boolean_value(value)
        when 'integer', 'integer_as_string', 'ordinal_as_string', 'unit_as_string', 'scale_as_string', 'long_as_string'
          integer_value(value)
        when /_list(_as_string)?\z/
          list_value(value)
        when 'string', 'base64', 'timestamp'
          value.to_s
        else
          value
        end
      end

      def cache_status_item(item)
        case item['sCI']
        when 'S0007' then @functional_position = item['s'] if item['n'] == 'status'
        when 'S0011' then @yellow_flash = item['s'] if item['n'] == 'status'
        when 'S0014' then cache_s0014_attribute(item)
        when 'S0015' then @traffic_situation = item['s'] if item['n'] == 'status'
        end
      end

      def cache_s0014_attribute(item)
        case item['n']
        when 'status' then @timeplan = item['s'].to_i
        when 'source' then @timeplan_source = item['s']
        end
      end
    end

    RSMP::SXL::Registry.register_interface SupervisorInterface
  end
end
