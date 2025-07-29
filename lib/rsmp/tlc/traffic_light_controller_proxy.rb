# Proxy for handling communication with a remote Traffic Light Controller (TLC)
# Provides high-level methods for interacting with TLC functionality

module RSMP
  module TLC
    class TrafficLightControllerProxy < SiteProxy

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
        main_component = find_main_component
        send_command main_component.c_id, command_list, options
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
        main_component = find_main_component
        request_status main_component.c_id, status_list, options
      end

      private

      # Find the main component of the TLC
      # @return [ComponentProxy] The main component
      # @raise [RuntimeError] If main component is not found
      def find_main_component
        main_component = @components.values.find { |component| component.grouped == true }
        raise "TLC main component not found" unless main_component
        main_component
      end
    end
  end
end