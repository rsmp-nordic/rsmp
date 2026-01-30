# Proxy for handling communication with a remote Traffic Light Controller (TLC).
# Provides high-level methods for interacting with TLC functionality.
# Acts as a mirror of the remote TLC by automatically subscribing to status updates.

module RSMP
  module TLC
    # Proxy for handling communication with a remote traffic light controller.
    class TrafficControllerProxy < SiteProxy
      attr_reader :timeplan_source, :timeplan, :timeouts

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
        @timeouts = node.supervisor_settings.dig('guest', 'timeouts') || {}
      end

      def handshake_complete
        super
        auto_subscribe_to_statuses
      end

      def subscribe_to_timeplan(options: {})
        validate_ready 'subscribe to timeplan'

        status_list = [{
          'sCI' => 'S0014',
          'n' => 'status',
          'sOc' => true
        }, {
          'sCI' => 'S0014',
          'n' => 'source',
          'sOc' => true
        }]

        merged_options = @timeouts.merge(options)

        raise 'TLC main component not found' unless main

        subscribe_to_status main.c_id, status_list, merged_options
      end

      # Override status update processing to automatically store timeplan values.
      def process_status_update(message)
        super

        status_values = message.attribute('sS')
        return unless status_values

        status_values.each do |item|
          next unless item['sCI'] == 'S0014'

          case item['n']
          when 'status'
            @timeplan = item['s'].to_i
          when 'source'
            @timeplan_source = item['s']
          end
        end
      end

      # Get all timeplan attributes stored in the main ComponentProxy.
      def timeplan_attributes
        main&.statuses&.dig('S0014') || {}
      end

      # Set the timeplan (signal plan) on the remote TLC
      def set_timeplan(plan_nr, options: {})
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

        send_command main.c_id, command_list, @timeouts.merge(options)
      end

      # Fetch the current signal plan from the remote TLC.
      def fetch_signal_plan(options: {})
        validate_ready 'fetch signal plan'

        status_list = [{
          'sCI' => 'S0014',
          'n' => 'status'
        }, {
          'sCI' => 'S0014',
          'n' => 'source'
        }]

        request_status main.c_id, status_list, @timeouts.merge(options)
      end

      private

      # Automatically subscribe to key TLC statuses to keep proxy in sync.
      def auto_subscribe_to_statuses
        subscribe_to_timeplan
      end

      def security_code_for(level)
        codes = @site_settings&.dig('security_codes') || {}
        code = codes[level] || codes[level.to_s]
        raise ArgumentError, "Security code for level #{level} is not configured" unless code

        code
      end
    end
  end
end
