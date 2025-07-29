#!/usr/bin/env ruby

# Example usage of TLCProxy class
# This demonstrates how to use the TLCProxy to interact with a remote TLC

require_relative '../lib/rsmp'

# Example of how to use TLCProxy with a real supervisor
# Note: This example requires a running TLC site to connect to

puts "TLCProxy Example"
puts "================"

# Configuration for connecting to a TLC
supervisor_settings = {
  'site_id' => 'RN+SU0001',
  'port' => 12111,
  'log' => {
    'active' => true,
    'color' => true,
    'level' => 'log'
  }
}

begin
  # This is a conceptual example showing how TLCProxy would be used
  # In a real scenario, you would:
  # 1. Start a supervisor
  # 2. Wait for a TLC site to connect 
  # 3. Get the site_proxy from the supervisor
  # 4. Create a TLCProxy instance

  puts "\nTLCProxy class loaded successfully!"
  puts "Methods available:"
  puts "  - set_signal_plan(plan_id, security_code: '0000', options: {})"
  puts "  - fetch_signal_plan(options: {})"
  
  # Example of creating a TLCProxy (with mock site_proxy)
  # In real use, site_proxy would come from supervisor.site_proxies
  puts "\n# Example instantiation:"
  puts "tlc_proxy = RSMP::TLCProxy.new(site_proxy, 'TC')"
  
  puts "\n# Example usage:"
  puts "# Set signal plan 3 with security code '1234'"
  puts "tlc_proxy.set_signal_plan(3, security_code: '1234')"
  
  puts "\n# Fetch current signal plan"
  puts "tlc_proxy.fetch_signal_plan"
  
  puts "\nTLCProxy ready for use!"
  
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace
end