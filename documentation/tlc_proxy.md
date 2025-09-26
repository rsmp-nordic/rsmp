# TLC Proxy

## Overview

The `RSMP::TLC::TrafficControllerProxy` is a specialized proxy class for handling communication with remote Traffic Light Controller (TLC) sites. It extends the base `SiteProxy` class to provide high-level methods for common TLC operations and **acts as a mirror of the remote TLC** by automatically subscribing to status updates to keep the proxy synchronized.

## Features

The TLC proxy provides convenient methods that abstract away the low-level RSMP message handling for common TLC operations:

### Signal Plan Management

- **`set_timeplan(plan_nr, security_code:, options: {})`** - Sets the active signal plan using M0002 command
- **`set_plan(plan_nr, security_code:, options: {})`** - Alias for `set_timeplan` for compatibility
- **`fetch_signal_plan(options: {})`** - Retrieves current signal plan information using S0014 status request

### Status Value Storage & Automatic Synchronization

The proxy automatically stores retrieved status values and provides convenient attribute readers:

- **`timeplan`** - The currently active signal plan number (Integer)
- **`current_plan`** - Alias for `timeplan` for compatibility (Integer) 
- **`plan_source`** - Source of current plan (String, e.g., "forced", "startup", "clock")
- **`timeplan_attributes`** - All S0014 attributes stored in the main component

### Automatic Status Subscription

The proxy **automatically subscribes to key TLC statuses** after connection is established:

- **Auto-subscribes to S0014** (timeplan status) with "update on change" 
- **Automatically processes status updates** to keep local values synchronized
- **Handles subscription cleanup** when the proxy is closed

### Additional Methods

- **`subscribe_to_timeplan(options: {})`** - Manually subscribe to S0014 status updates
- **`unsubscribe_all()`** - Unsubscribe from all auto-subscriptions

### Timeout Configuration

The proxy accepts a `timeouts` configuration option for RSMP operations:

```ruby
timeouts = {
  'watchdog' => 0.2,
  'acknowledgement' => 0.2,
  'command_timeout' => 5.0
}

proxy = TrafficControllerProxy.new(
  supervisor: supervisor,
  ip: '127.0.0.1', 
  port: 12345,
  site_id: 'TLC001',
  timeouts: timeouts
)
```

## Automatic Detection

When a TLC site connects to a supervisor, the supervisor automatically detects that it's a TLC based on the site configuration (`type: 'tlc'`) and creates a `TrafficControllerProxy` instead of a generic `SiteProxy`.

This happens in the supervisor's connection handling:

```ruby
# In supervisor configuration
supervisor_settings = {
  'sites' => {
    'TLC001' => { 'sxl' => 'tlc', 'type' => 'tlc' }
  },
  'guest' => { 'sxl' => 'tlc', 'type' => 'tlc' }  # For unknown TLC sites
}

# When TLC001 connects, supervisor creates TLCProxy automatically
tlc_proxy = supervisor.wait_for_site('TLC001')
# tlc_proxy is now an instance of TrafficControllerProxy
```

## Usage Examples

### Setting a Signal Plan

```ruby
# Set signal plan 3 with security code using new method name
result = tlc_proxy.set_timeplan(3, security_code: '2222')

# Or use the compatibility alias
result = tlc_proxy.set_plan(3, security_code: '2222')

# Set plan and collect the response
result = tlc_proxy.set_timeplan(2, 
  security_code: '2222', 
  options: { collect: { timeout: 5 } }
)

# Check if command was successful
if result[:collector].ok?
  puts "Signal plan changed successfully"
else
  puts "Failed to change signal plan"
end
```

### Fetching Current Signal Plan

```ruby
# Get current signal plan information and store in proxy
result = tlc_proxy.fetch_signal_plan(options: { collect: { timeout: 5 } })

if result[:collector].ok?
  # Status values are automatically stored in the proxy
  puts "Current signal plan: #{tlc_proxy.timeplan}"
  puts "Plan source: #{tlc_proxy.plan_source}"
else
  puts "Failed to retrieve signal plan status"
end

# You can also access the raw response if needed
response = result[:collector].messages.first
status_items = response.attribute('sS')
```

### Accessing Stored Status Values

```ruby
# Status values are automatically updated when:
# 1. fetch_signal_plan is called with collection
# 2. Status updates are received from subscriptions

# Access the stored values directly  
puts "Current plan: #{tlc_proxy.timeplan}"
puts "Current plan (alias): #{tlc_proxy.current_plan}"
puts "Plan source: #{tlc_proxy.plan_source}"

# Get all timeplan attributes from the component
attributes = tlc_proxy.timeplan_attributes
puts "All S0014 attributes: #{attributes}"

# Values persist until updated by new data
puts "Plan is still: #{tlc_proxy.timeplan}" # Same value
```

### Manual Subscription Management

```ruby
# The proxy automatically subscribes to timeplan status, but you can also:

# Manually subscribe (usually not needed)
tlc_proxy.subscribe_to_timeplan

# Unsubscribe from all auto-subscriptions
tlc_proxy.unsubscribe_all
```

### Error Handling

```ruby
begin
  result = tlc_proxy.set_plan(5, security_code: 'wrong_code')
rescue RSMP::NotReady
  puts "TLC is not ready for commands"
rescue RSMP::MessageRejected => e
  puts "Command rejected: #{e.message}"
end
```

## RSMP Message Details

### M0002 - Set Signal Plan

The `set_plan` method sends an M0002 command with the following parameters:

- `status`: "True" (activate the plan)
- `securityCode`: The provided security code
- `timeplan`: The signal plan number

### S0014 - Signal Plan Status

The `fetch_signal_plan` method requests S0014 status with:

- `status`: Current active signal plan number
- `source`: Source of the current plan (e.g., "forced", "startup", "clock")

## Integration with Existing Code

The TLC proxy seamlessly integrates with existing RSMP infrastructure:

- Inherits all base functionality from `SiteProxy`
- Uses existing message sending and collection mechanisms
- Works with existing logging and error handling
- Compatible with all existing proxy configuration options

## Testing

Comprehensive tests are included:

- Unit tests for method behavior and parameter validation
- Integration tests with real TLC site connections
- Error handling and edge case testing
- Supervisor proxy creation testing

## Implementation Notes

- The TLC proxy automatically finds the main TLC component (grouped component)
- All security and validation is handled by the underlying TLC site implementation
- The proxy provides a cleaner API while maintaining full RSMP protocol compliance
- Fiber-safe and async-compatible with the rest of the RSMP framework