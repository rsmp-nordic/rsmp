# Proxy for handling communication with a remote Traffic Light Controller (TLC).
# Provides high-level methods for interacting with TLC functionality.
# Acts as a mirror of the remote TLC by automatically subscribing to status updates.

module RSMP
  module TLC
    # Proxy for handling communication with a remote traffic light controller.
    class TrafficControllerProxy < SiteProxy
      include Proxy::Control
      include Proxy::IO
      include Proxy::Plans
      include Proxy::Status
      include Proxy::Detectors
      include Proxy::System

      attr_reader :timeplan_source, :timeplan, :timeouts,
                  :functional_position, :yellow_flash, :traffic_situation

      # Backwards-compatible accessors expected by tests and callers
      def current_plan
        @timeplan
      end

      def plan_source
        @timeplan_source
      end

      def initialize(options)
        super
        @timeplan_source = nil
        @timeplan = nil
        @functional_position = nil
        @yellow_flash = nil
        @traffic_situation = nil
        @timeouts = node.supervisor_settings.dig('default', 'timeouts') || {}
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

      # Override status update processing to automatically store cached status values.
      def process_status_update(message)
        super

        status_values = message.attribute('sS')
        return unless status_values

        status_values.each { |item| cache_status_item(item) }
      end

      # Get all timeplan attributes stored in the main ComponentProxy.
      def timeplan_attributes
        main&.statuses&.dig('S0014') || {}
      end

      # Returns true if sOc (send on change) should be used.
      # sOc is supported in RSMP core version 3.1.5 and later.
      def use_soc?
        return false unless core_version

        RSMP::Proxy.version_meets_requirement?(core_version, '>=3.1.5')
      end

      private

      # Automatically subscribe to key TLC statuses to keep proxy in sync.
      def auto_subscribe_to_statuses
        return unless main

        subscribe_to_timeplan
        subscribe_to_key_statuses
      end

      # Look up security code for a given level from site settings.
      # Expects @site_settings['security_codes'] = { 1 => 'code1', 2 => 'code2' }
      def security_code_for(level)
        codes = @site_settings&.dig('security_codes') || {}
        code = codes[level] || codes[level.to_s]
        raise ArgumentError, "Security code for level #{level} is not configured" unless code

        code
      end

      # Send a command and optionally wait for the CommandResponse and confirming status updates.
      #
      # confirm_description - human-readable label used in log output
      # confirm_status_list  - status items to wait for (passed to wait_for_status);
      #                        may be nil if only a CommandResponse confirmation is needed
      # within:              - timeout in seconds; if set, collects the CommandResponse
      def send_command_with_confirm(component_id, command_list, confirm_description, confirm_status_list,
                                    within: nil)
        result = if within
                   send_command component_id, command_list, within: within
                 else
                   send_command component_id, command_list
                 end

        return result if confirm_status_list.nil? || confirm_status_list.empty? || within.nil?

        wait_for_status confirm_description, confirm_status_list, timeout: within

        result
      end

      # Process a single status item and update the corresponding cached value.
      def cache_status_item(item)
        case item['sCI']
        when 'S0007' then @functional_position = item['s'] if item['n'] == 'status'
        when 'S0011' then @yellow_flash = item['s'] if item['n'] == 'status'
        when 'S0014' then cache_s0014_attribute(item)
        when 'S0015' then @traffic_situation = item['s'] if item['n'] == 'status'
        end
      end

      # Update cached values for S0014 (timeplan) status attributes.
      def cache_s0014_attribute(item)
        case item['n']
        when 'status' then @timeplan = item['s'].to_i
        when 'source' then @timeplan_source = item['s']
        end
      end
    end
  end
end
