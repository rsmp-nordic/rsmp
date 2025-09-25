# Proxy for handling communication with a remote Traffic Light Controller (TLC)
# Provides high-level methods for interacting with TLC functionality

module RSMP
  module TLC
    class TrafficControllerProxy < SiteProxy
      
      # Attribute readers for current status values
      attr_reader :current_plan, :plan_source
      
      def initialize(options)
        super(options)
        @current_plan = nil
        @plan_source = nil
      end

      # Set the signal plan on the remote TLC
      # @param plan_nr [Integer] The signal plan number to set
      # @param security_code [String] Security code for authentication
      # @param options [Hash] Additional options for the command
      # @return [Hash] Result containing sent message and optional collector
      def set_plan(plan_nr, security_code:, options: {})
        validate_ready 'set signal plan'
        
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

        # Use the main component (TLC controller)
        raise "TLC main component not found" unless main
        send_command main.c_id, command_list, options
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

        # Use the main component (TLC controller)
        raise "TLC main component not found" unless main
        result = request_status main.c_id, status_list, options
        
        # If a collector was used, wait for the response and store the values
        if result&.dig(:collector) && options[:collect] != false
          status_response = result[:collector].wait
          if status_response&.dig('sS')
            status_values = status_response['sS']
            status_value = status_values.find { |s| s['n'] == 'status' }
            source_value = status_values.find { |s| s['n'] == 'source' }
            
            @current_plan = status_value['s'].to_i if status_value
            @plan_source = source_value['s'] if source_value
          end
        end
        
        result
      end
    end
  end
end