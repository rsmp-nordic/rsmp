# TLC Proxy for interacting with remote Traffic Light Controllers
# Provides high-level methods for common TLC operations

module RSMP
  class TLCProxy
    attr_reader :site_proxy, :component_id

    # Initialize with a SiteProxy that represents the connection to the remote TLC
    # component_id: The main component ID of the TLC (usually 'TC')
    def initialize(site_proxy, component_id = 'TC')
      @site_proxy = site_proxy
      @component_id = component_id
    end

    # Set the signal plan using M0002 command
    # plan_id: Integer representing the signal plan number to activate
    # security_code: Security code required for the operation (default: '0000')
    # options: Hash of options to pass to send_command
    # Returns the command response collector for tracking the response
    def set_signal_plan(plan_id, security_code: '0000', options: {})
      command_list = [
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'status', 'v' => 'True' },
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'securityCode', 'v' => security_code.to_s },
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'timeplan', 'v' => plan_id.to_s }
      ]
      
      @site_proxy.send_command(@component_id, command_list, options)
    end

    # Fetch the current signal plan using S0014 status request
    # options: Hash of options to pass to request_status
    # Returns status collector for tracking the response
    def fetch_signal_plan(options: {})
      status_list = [
        { 'sCI' => 'S0014', 'n' => 'status' },
        { 'sCI' => 'S0014', 'n' => 'source' }
      ]
      
      @site_proxy.request_status(@component_id, status_list, options)
    end
  end
end