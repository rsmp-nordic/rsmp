# Proxy for handling communication with a remote Traffic Light Controller (TLC).
# Provides high-level methods for interacting with TLC functionality.
# Acts as a mirror of the remote TLC by automatically subscribing to status updates.

module RSMP
  module TLC
    # Proxy for handling communication with a remote traffic light controller.
    class TrafficControllerProxy < SiteProxy
      # Attribute readers for current status values.
      attr_reader :current_plan, :plan_source, :timeplan, :timeouts

      def initialize(options)
        super
        @current_plan = nil
        @plan_source = nil
        @timeplan = nil
        @timeouts = node.supervisor_settings.dig('guest', 'timeouts') || {}
      end

      def handshake_complete
        super
        auto_subscribe_to_statuses
      end

      # Subscribe to S0014 timeplan status updates.
      # This will cause the remote site to send status updates when the timeplan changes.
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

        return unless message.attribute('cId') == main&.c_id

        status_values = message.attribute('sS')
        return unless status_values

        status_values.each do |item|
          next unless item['sCI'] == 'S0014'

          case item['n']
          when 'status'
            @timeplan = item['s'].to_i
            @current_plan = @timeplan
          when 'source'
            @plan_source = item['s']
          end
        end
      end

      # Get all timeplan attributes stored in the main ComponentProxy.
      def timeplan_attributes
        return {} unless main

        main.statuses&.dig('S0014') || {}
      end

      # Set the timeplan (signal plan) on the remote TLC.
      # @param plan_nr [Integer] The signal plan number to set.
      # @param security_code [String] Security code for authentication.
      # @param options [Hash] Additional options for the command.
      # @return [Hash] Result containing sent message and optional collector.
      def set_timeplan(plan_nr, security_code:, options: {})
        validate_ready 'set timeplan'

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

        merged_options = @timeouts.merge(options)

        raise 'TLC main component not found' unless main

        send_command main.c_id, command_list, merged_options
      end

      # Fetch the current signal plan from the remote TLC.
      # @param options [Hash] Additional options for the status request.
      # @return [Hash] Result containing sent message and optional collector.
      def fetch_signal_plan(options: {})
        validate_ready 'fetch signal plan'

        status_list = [{
          'sCI' => 'S0014',
          'n' => 'status'
        }, {
          'sCI' => 'S0014',
          'n' => 'source'
        }]

        merged_options = @timeouts.merge(options)

        raise 'TLC main component not found' unless main

        request_status main.c_id, status_list, merged_options
      end

      # Override close to clean up subscriptions.
      def close
        unsubscribe_all
        super
      end

      private

      # Automatically subscribe to key TLC statuses to keep proxy in sync.
      def auto_subscribe_to_statuses
        subscribe_to_timeplan
      rescue StandardError => e
        log "Failed to auto-subscribe to timeplan status: #{e.message}", level: :warning
      end
    end
  end
end
