module RSMP
  module TLC
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
