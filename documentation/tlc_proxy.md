# TLC Proxy

The `TLCProxy` class provides a high-level interface for interacting with remote Traffic Light Controllers (TLCs) via the RSMP protocol. It extends the `SiteProxy` class with TLC-specific methods that encapsulate common TLC operations.

## Overview

The TLC Proxy acts as a client-side representation of a remote traffic light controller. When you run an RSMP supervisor and a TLC connects, you can use the TLC proxy to send commands and requests to the remote TLC in a convenient way.

Instead of manually constructing RSMP command and status messages, the TLC proxy provides simple method calls that handle the message formatting for you.

## Usage

### Creating a TLC Proxy

The TLC Proxy is typically created automatically when a TLC connects to your supervisor. However, you can also create one manually:

```ruby
require 'rsmp'

# Create TLC proxy (typically done automatically by supervisor)
tlc_proxy = RSMP::TLCProxy.new(
  supervisor: supervisor,
  site_id: 'TLC_001',
  ip: '192.168.1.100',
  port: 12345
)
```

### Changing Signal Plans

Use the `change_signal_plan` method to switch the TLC to a different time plan:

```ruby
# Switch to time plan 3 using security code "1234"
result = tlc_proxy.change_signal_plan(3, "1234")

# With options for collecting the response
result = tlc_proxy.change_signal_plan(3, "1234", collect: { timeout: 10 })
response = result[:collector].wait
puts "Command executed successfully" if response
```

This sends an M0002 "setPlan" command with:
- `status`: "True" (use command instead of programming)
- `securityCode`: The provided security code (level 2 required)
- `timeplan`: The time plan number to activate

### Fetching Current Signal Plan

Use the `fetch_signal_plan` method to get the current active signal plan:

```ruby
# Request current signal plan information
result = tlc_proxy.fetch_signal_plan(collect: { timeout: 5 })
response = result[:collector].wait

if response
  status_data = response.attributes['sS']
  current_plan = status_data.find { |s| s['n'] == 'status' }['s']
  plan_source = status_data.find { |s| s['n'] == 'source' }['s']
  
  puts "Current time plan: #{current_plan}"
  puts "Set by: #{plan_source}"
end
```

This sends an S0014 status request for:
- `status`: The current active time plan number (1-255)
- `source`: How the plan was set (operator_panel, calendar_clock, control_block, forced, startup, other)

## Error Handling

Both methods will raise a `NotReady` exception if the connection to the TLC is not established or ready:

```ruby
begin
  tlc_proxy.change_signal_plan(3, "1234")
rescue RSMP::NotReady => e
  puts "TLC connection not ready: #{e.message}"
end
```

## Security Codes

The `change_signal_plan` method requires a security code level 2. This is an additional security measure defined in the RSMP SXL specification for traffic light controllers. The security code must match what is configured on the TLC.

## Component Identification

Both methods automatically determine the component ID to use:
- If a main component exists, its ID is used
- Otherwise, "main" is used as the default component ID

This follows the typical TLC configuration where commands are sent to the main traffic controller component.

## Integration with Existing RSMP Features

The TLC Proxy methods integrate seamlessly with existing RSMP features:

- **Message Collection**: Use the `:collect` option to wait for and capture responses
- **Validation**: Use the `:validate` option to enable/disable message validation  
- **Timeouts**: Configure timeouts through the collection options
- **Error Handling**: Standard RSMP error handling applies

## Example: Complete TLC Interaction

```ruby
# Establish connection and change signal plan
begin
  # Switch to time plan for rush hour traffic
  puts "Switching to rush hour time plan..."
  result = tlc_proxy.change_signal_plan(5, "rush_hour_code", collect: { timeout: 10 })
  
  # Wait for confirmation
  if result[:collector].wait
    puts "✓ Successfully switched to time plan 5"
    
    # Verify the change
    verification = tlc_proxy.fetch_signal_plan(collect: { timeout: 5 })
    if response = verification[:collector].wait
      status_data = response.attributes['sS']
      current_plan = status_data.find { |s| s['n'] == 'status' }['s']
      puts "✓ Verified current plan: #{current_plan}"
    end
  else
    puts "✗ Failed to change time plan"
  end
  
rescue RSMP::NotReady => e
  puts "✗ TLC not ready: #{e.message}"
rescue StandardError => e
  puts "✗ Error: #{e.message}"
end
```

This high-level interface makes it much easier to interact with TLCs compared to manually constructing RSMP messages, while still providing access to all the underlying RSMP features when needed.