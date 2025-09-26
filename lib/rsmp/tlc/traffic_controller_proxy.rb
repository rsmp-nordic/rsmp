# Proxy for handling communication with a remote Traffic Light Controller (TLC)
# Provides high-level methods for interacting with TLC functionality
# Acts as a mirror of the remote TLC by automatically subscribing to status updates

module RSMP
  module TLC
    class TrafficControllerProxy < SiteProxy
      
      # Attribute readers for current status values
      attr_reader :current_plan, :plan_source, :timeplan, :timeouts
      
      def initialize(options)
        super(options)
        @current_plan = nil
        @plan_source = nil
        @timeplan = nil
        @timeouts = options[:timeouts] || {}
        
        # Schedule auto-subscription after handshake is complete
        # This will be called once the connection is established
      end
      
      def handshake_complete
        super
        # Auto-subscribe to default statuses after connection is established
        auto_subscribe_to_statuses
      end
      
      private
      
      # Automatically subscribe to key TLC statuses to keep proxy in sync
      def auto_subscribe_to_statuses
        begin
          subscribe_to_timeplan
        rescue => e
          log "Failed to auto-subscribe to timeplan status: #{e.message}", level: :warn
        end
      end
      
      public
      
      # Subscribe to S0014 timeplan status updates
      # This will cause the remote site to send status updates when the timeplan changes
      def subscribe_to_timeplan(options: {})
        validate_ready 'subscribe to timeplan'
        
        status_list = [{
          "sCI" => "S0014",
          "n" => "status",
          "sOc" => true  # Update on change
        }, {
          "sCI" => "S0014", 
          "n" => "source",
          "sOc" => true  # Update on change
        }]
        
        # Use configured timeouts if available
        merged_options = @timeouts.merge(options)
        
        # Use the main component (TLC controller)
        raise "TLC main component not found" unless main
        
        result = subscribe_to_status main.c_id, status_list, merged_options
        result
      end
      
      # Override status update processing to automatically store timeplan values
      def process_status_update(message)
        super(message)  # Let parent handle the standard processing
        
        # Check if this is an S0014 update and store timeplan values
        if message.attribute("cId") == main&.c_id
          status_values = message.attribute('sS')
          if status_values
            status_values.each do |item|
              if item['sCI'] == 'S0014'
                case item['n']
                when 'status'
                  @timeplan = item['s'].to_i
                  @current_plan = @timeplan  # Keep compatibility with existing attr
                when 'source'
                  @plan_source = item['s']
                end
              end
            end
          end
        end
      end
      
      # Get the current timeplan number
      def timeplan
        @timeplan
      end
      
      # Get all timeplan attributes stored in the main ComponentProxy
      def timeplan_attributes
        return {} unless main
        main.instance_variable_get(:@statuses)&.dig('S0014') || {}
      end
      
      # Set the timeplan (signal plan) on the remote TLC
      # @param plan_nr [Integer] The signal plan number to set
      # @param security_code [String] Security code for authentication
      # @param options [Hash] Additional options for the command
      # @return [Hash] Result containing sent message and optional collector
      def set_timeplan(plan_nr, security_code:, options: {})
        validate_ready 'set timeplan'
        
        command_list = [{
          "cCI" => "M0002",
          "cO" => "setPlan",
          "n" => "status",
          "v" => "True"
        }, {
          "cCI" => "M0002", 
          "cO" => "setPlan",
          "n" => "securityCode",
          "v" => security_code.to_s
        }, {
          "cCI" => "M0002",
          "cO" => "setPlan", 
          "n" => "timeplan",
          "v" => plan_nr.to_s
        }]

        # Use configured timeouts if available
        merged_options = @timeouts.merge(options)

        # Use the main component (TLC controller)
        raise "TLC main component not found" unless main
        result = send_command main.c_id, command_list, merged_options
        
        # Update local timeplan value if command response includes updated values
        if result[:collector] && merged_options[:collect] != false
          begin
            response = result[:collector].wait
            # The M0002 command response may include updated status values
            # which will be processed automatically by the standard message handling
          rescue => e
            log "Failed to collect command response: #{e.message}", level: :warn
          end
        end
        
        result
      end

      # Fetch the current signal plan from the remote TLC
      # @param options [Hash] Additional options for the status request
      # @return [Hash] Result containing sent message and optional collector
      def fetch_signal_plan(options: {})
        validate_ready 'fetch signal plan'
        
        status_list = [{
          "sCI" => "S0014",
          "n" => "status"
        }, {
          "sCI" => "S0014", 
          "n" => "source"
        }]

        # Use configured timeouts if available
        merged_options = @timeouts.merge(options)

        # Use the main component (TLC controller)
        raise "TLC main component not found" unless main
        result = request_status main.c_id, status_list, merged_options
        
        # If a collector was used, wait for the response and store the values
        if result&.dig(:collector) && merged_options[:collect] != false
          status_response = result[:collector].wait
          if status_response&.dig('sS')
            status_values = status_response['sS']
            status_value = status_values.find { |s| s['n'] == 'status' }
            source_value = status_values.find { |s| s['n'] == 'source' }
            
            @timeplan = status_value['s'].to_i if status_value
            @current_plan = @timeplan  # Keep compatibility
            @plan_source = source_value['s'] if source_value
          end
        end
        
        result
      end
      
      # Override close to clean up subscriptions
      def close
        unsubscribe_all  # Uses parent's unsubscribe_all method
        super
      end
    end
  end
end