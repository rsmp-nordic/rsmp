#!/usr/bin/env ruby

# Example script demonstrating TLCProxy usage
# This would typically be used when running an RSMP supervisor that connects to a remote TLC

require 'rsmp'

# Mock setup for demonstration - in real usage you'd have an actual supervisor
class MockSupervisor
  attr_reader :supervisor_settings
  
  def initialize
    @supervisor_settings = {
      'guest' => {
        'sxl' => 'tlc',
        'intervals' => { 'timer' => 0.1, 'watchdog' => 0.1 },
        'timeouts' => { 'watchdog' => 0.2, 'acknowledgement' => 0.2 }
      }
    }
  end
end

# Create a TLC proxy for interacting with a remote traffic light controller
def demonstrate_tlc_proxy
  puts "=== RSMP TLC Proxy Demonstration ==="
  
  # Setup
  supervisor = MockSupervisor.new
  site_id = 'RN+SI0001'  # Remote TLC site ID
  
  # Create TLC proxy - this would connect to a remote TLC in real usage
  tlc_proxy = RSMP::TLCProxy.new(supervisor: supervisor, site_id: site_id)
  
  # In real usage, you'd establish connection here
  puts "Connected to TLC site: #{site_id}"
  
  # Example 1: Change to signal plan 3
  puts "\n1. Changing to signal plan 3..."
  
  # The M0002 command will be formatted automatically
  begin
    command_request = tlc_proxy.set_plan(3, security_code: '2222')
    puts "✓ Signal plan change command sent successfully"
    puts "  Command format: M0002 with plan=3, security_code=2222"
  rescue => e
    puts "✗ Failed to send command: #{e.message}"
  end
  
  # Example 2: Fetch current signal plan status
  puts "\n2. Fetching current signal plan status..."
  
  # The S0014 status request will be formatted automatically
  begin
    status_request = tlc_proxy.fetch_signal_plan
    puts "✓ Signal plan status request sent successfully"
    puts "  Status format: S0014 requesting 'status' and 'source'"
  rescue => e
    puts "✗ Failed to request status: #{e.message}"
  end
  
  # Example 3: Using custom component ID and options
  puts "\n3. Advanced usage with custom options..."
  
  begin
    tlc_proxy.set_plan(1, 
      security_code: '2222',
      component_id: 'TC',
      timeout: 5,
      collect: true
    )
    puts "✓ Advanced command sent with custom component ID and options"
  rescue => e
    puts "✗ Failed to send advanced command: #{e.message}"
  end
  
  puts "\n=== Demonstration Complete ==="
  puts "\nThe TLC proxy provides a high-level interface for:"
  puts "- Changing signal plans (M0002 command)"
  puts "- Fetching signal plan status (S0014 status request)"
  puts "- Handling RSMP message formatting automatically"
  puts "- Simplifying remote TLC interaction for supervisors"
end

# Run the demonstration
if __FILE__ == $0
  demonstrate_tlc_proxy
end