# TLC Proxy

## Overview

The `RSMP::TLC::TrafficControllerProxy` is a specialized proxy class for handling communication with remote Traffic Light Controller (TLC) sites. It extends the base `SiteProxy` class to provide high-level methods for common TLC operations.

## Features

The TLC proxy provides convenient methods that abstract away the low-level RSMP message handling for common TLC operations:

### Signal Plan Management

- **`set_plan(plan_nr, security_code:, options: {})`** - Sets the active signal plan using M0002 command
- **`fetch_signal_plan(options: {})`** - Retrieves current signal plan information using S0014 status request

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
# Set signal plan 3 with security code
result = tlc_proxy.set_plan(3, security_code: '2222')

# Set plan and collect the response
result = tlc_proxy.set_plan(2, 
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
# Get current signal plan information
result = tlc_proxy.fetch_signal_plan(collect: { timeout: 5 })

if result[:collector].ok?
  response = result[:collector].messages.first
  status_items = response.attribute('sS')
  
  # Find current plan and source
  current_plan = status_items.find { |item| item['n'] == 'status' }['s']
  plan_source = status_items.find { |item| item['n'] == 'source' }['s']
  
  puts "Current signal plan: #{current_plan} (source: #{plan_source})"
end
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