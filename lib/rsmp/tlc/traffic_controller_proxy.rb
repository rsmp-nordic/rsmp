# Proxy for handling communication with a remote Traffic Light Controller (TLC)
# Provides high-level methods for interacting with TLC functionality

module RSMP
  module TLC
    class TrafficControllerProxy < SiteProxy

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
        raise "TLC main component not found" unless @main
        send_command @main.c_id, command_list, options
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
        raise "TLC main component not found" unless @main
        request_status @main.c_id, status_list, options
      end
    end
  end
end