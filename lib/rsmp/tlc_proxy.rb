module RSMP
  # TLCProxy provides a high-level interface for interacting with a remote Traffic Light Controller (TLC)
  # through RSMP messages. It extends SiteProxy to provide TLC-specific methods.
  class TLCProxy < SiteProxy
    
    # Constructor
    def initialize(options)
      super(options)
    end

    # Change the signal plan of the TLC using M0002 command
    # 
    # @param plan_number [Integer] The signal plan number to activate
    # @param security_code [String] Security code for level 2 authentication
    # @param component_id [String] Component ID, defaults to main component
    # @param options [Hash] Additional options for the command
    # @return [RSMP::CommandRequest] The command request message
    def set_plan(plan_number, security_code:, component_id: nil, **options)
      component_id ||= main&.c_id || 'main'
      
      command_list = [{
        'cCI' => 'M0002',
        'cO' => 'setPlan',
        'n' => 'status',
        'v' => 'True'
      }, {
        'cCI' => 'M0002',
        'cO' => 'setPlan', 
        'n' => 'securityCode',
        'v' => security_code
      }, {
        'cCI' => 'M0002',
        'cO' => 'setPlan',
        'n' => 'timeplan',
        'v' => plan_number.to_s
      }]

      send_command(component_id, command_list, options)
    end

    # Fetch the current signal plan using S0014 status request
    #
    # @param component_id [String] Component ID, defaults to main component  
    # @param options [Hash] Additional options for the status request
    # @return [RSMP::StatusRequest] The status request message
    def fetch_signal_plan(component_id: nil, **options)
      component_id ||= main&.c_id || 'main'
      
      status_list = [{
        'sCI' => 'S0014',
        'n' => 'status'
      }, {
        'sCI' => 'S0014', 
        'n' => 'source'
      }]

      request_status(component_id, status_list, options)
    end
  end
end