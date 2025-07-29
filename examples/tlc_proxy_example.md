# TLC Proxy Example

This example demonstrates how to use the new `TLCProxy` class to interact with a remote Traffic Light Controller (TLC) through RSMP messages.

## Overview

The `TLCProxy` extends `SiteProxy` and provides high-level methods for common TLC operations:

- `set_plan(plan_number, security_code:)` - Changes the signal plan using M0002 command
- `fetch_signal_plan()` - Retrieves current signal plan using S0014 status request

## Usage Example

```ruby
require 'rsmp'

# Setup supervisor and connect to TLC
supervisor_settings = {
  'guest' => {
    'sxl' => 'tlc',
    'intervals' => { 'timer' => 0.1, 'watchdog' => 0.1 },
    'timeouts' => { 'watchdog' => 0.2, 'acknowledgement' => 0.2 }
  }
}

supervisor = double('supervisor', supervisor_settings: supervisor_settings)
site_id = 'RN+SI0001'

# Create TLC proxy
tlc_proxy = RSMP::TLCProxy.new(supervisor: supervisor, site_id: site_id)

# Change to signal plan 3 with security code
response = tlc_proxy.set_plan(3, security_code: '2222')

# Fetch current signal plan status
status = tlc_proxy.fetch_signal_plan

# You can also specify component ID and additional options
tlc_proxy.set_plan(2, 
  security_code: '2222', 
  component_id: 'TC', 
  timeout: 5
)

tlc_proxy.fetch_signal_plan(
  component_id: 'TC',
  collect: true,
  timeout: 10
)
```

## Method Details

### set_plan(plan_number, security_code:, component_id: nil, **options)

Changes the TLC signal plan using the M0002 command.

**Parameters:**
- `plan_number` (Integer): The signal plan number to activate
- `security_code` (String): Security code for level 2 authentication  
- `component_id` (String, optional): Component ID, defaults to main component
- `**options`: Additional options passed to the underlying `send_command` method

**Returns:** The command request message

### fetch_signal_plan(component_id: nil, **options)

Fetches the current signal plan using the S0014 status request.

**Parameters:**
- `component_id` (String, optional): Component ID, defaults to main component
- `**options`: Additional options passed to the underlying `request_status` method

**Returns:** The status request message

## RSMP Message Details

### M0002 Command Format
```ruby
[{
  'cCI' => 'M0002',
  'cO' => 'setPlan',
  'n' => 'status',
  'v' => 'True'
}, {
  'cCI' => 'M0002',
  'cO' => 'setPlan', 
  'n' => 'securityCode',
  'v' => '2222'
}, {
  'cCI' => 'M0002',
  'cO' => 'setPlan',
  'n' => 'timeplan',
  'v' => '3'
}]
```

### S0014 Status Request Format
```ruby
[{
  'sCI' => 'S0014',
  'n' => 'status'
}, {
  'sCI' => 'S0014', 
  'n' => 'source'
}]
```

## References

- [M0002 Documentation](https://rsmp-nordic.github.io/rsmp_sxl_traffic_lights/1.2.1/sxl_traffic_light_controller.html#m0002)
- [S0014 Documentation](https://rsmp-nordic.github.io/rsmp_sxl_traffic_lights/1.2.1/sxl_traffic_light_controller.html#s0014)