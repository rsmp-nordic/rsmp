# Handles a supervisor connection to a remote TLC (Traffic Light Controller)
# This class extends SiteProxy to provide TLC-specific methods for interacting
# with traffic light controllers using the RSMP SXL traffic lights protocol.

module RSMP
  class TLCProxy < SiteProxy
    
    # Change the signal plan of the TLC using command M0002
    # 
    # Sends an M0002 "setPlan" command to change the active signal plan (time plan)
    # of the traffic light controller. This requires security code level 2.
    #
    # @param timeplan [Integer] Time plan number (1-255) to activate
    # @param security_code [String] Security code level 2 required for the command
    # @param options [Hash] Optional parameters for command sending (e.g. :collect, :validate)
    # @return [Hash] Result containing :sent message and optional :collector
    # @raise [NotReady] if the connection is not ready
    # @example
    #   tlc.change_signal_plan(3, "1234")  # Switch to time plan 3
    def change_signal_plan(timeplan, security_code, options = {})
      validate_ready 'change signal plan'
      
      command_list = [{
        "cCI" => "M0002",
        "cO" => "setPlan", 
        "n" => "status",
        "v" => "True"
      }, {
        "cCI" => "M0002",
        "cO" => "setPlan",
        "n" => "securityCode", 
        "v" => security_code
      }, {
        "cCI" => "M0002",
        "cO" => "setPlan",
        "n" => "timeplan",
        "v" => timeplan.to_s
      }]
      
      component_id = main ? main.c_id : "main"
      send_command(component_id, command_list, options)
    end
    
    # Fetch the current signal plan of the TLC using status S0014
    # 
    # Sends an S0014 status request to get the current active signal plan 
    # and its source (how it was set - manually, by schedule, etc.).
    #
    # @param options [Hash] Optional parameters for status request (e.g. :collect, :validate)
    # @return [Hash] Result containing :sent message and optional :collector
    # @raise [NotReady] if the connection is not ready  
    # @example
    #   result = tlc.fetch_signal_plan(collect: { timeout: 5 })
    #   # Access response via result[:collector].messages when using collect
    def fetch_signal_plan(options = {})
      validate_ready 'fetch signal plan'
      
      status_list = [{
        "sCI" => "S0014",
        "n" => "status"
      }, {
        "sCI" => "S0014", 
        "n" => "source"
      }]
      
      component_id = main ? main.c_id : "main"
      request_status(component_id, status_list, options)
    end
  end
end