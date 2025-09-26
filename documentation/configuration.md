# RSMP Configuration System

The RSMP gem provides a structured configuration system for managing settings for Sites and Supervisors. The configuration system includes:

- **Hierarchical defaults** - Sensible defaults for all configuration options
- **JSON schema validation** - Runtime validation of configuration values
- **Type-safe accessors** - Convenient methods to access configuration values
- **File-based configuration** - Load configuration from YAML files
- **Deep merging** - Override specific configuration values while preserving defaults

## Configuration Classes

### RSMP::Options::BaseOptions

The base class providing common functionality for all configuration options:

```ruby
# Create with hash
options = RSMP::Options::BaseOptions.new({'key' => 'value'})

# Create from YAML file
options = RSMP::Options::BaseOptions.new('/path/to/config.yaml')

# Access values
value = options.get('key')
nested_value = options.get('nested.key')

# Set values
options.set('key', 'new_value')
options.set('nested.new_key', 'value')

# Merge additional configuration
options.merge!({'additional' => 'config'})

# Get complete configuration as hash
hash = options.to_h
```

### RSMP::Options::SiteOptions

Configuration options specific to RSMP Site instances:

```ruby
# Create with defaults
site_options = RSMP::Options::SiteOptions.new

# Create with custom configuration
site_options = RSMP::Options::SiteOptions.new({
  'site_id' => 'MY+SITE001',
  'supervisors' => [
    { 'ip' => '192.168.1.100', 'port' => 12111 }
  ],
  'sxl' => 'tlc',
  'intervals' => {
    'timer' => 0.5
  }
})

# Convenient accessors
puts site_options.site_id           # => 'MY+SITE001'
puts site_options.sxl               # => 'tlc'
puts site_options.sxl_version       # => '1.2.1'
puts site_options.supervisors       # => [{"ip"=>"192.168.1.100", "port"=>12111}]
puts site_options.send_after_connect? # => true

# Modify configuration
site_options.site_id = 'NEW+ID'
site_options.supervisors = [{'ip' => '10.0.0.1', 'port' => 13111}]
```

#### Default Configuration

```yaml
site_id: RN+SI0001
supervisors:
  - ip: 127.0.0.1
    port: 12111
sxl: tlc
sxl_version: 1.2.1  # Latest available version
intervals:
  timer: 0.1
  watchdog: 1
  reconnect: 0.1
timeouts:
  watchdog: 2
  acknowledgement: 2
send_after_connect: true
components:
  main:
    C1: {}
```

### RSMP::Options::SupervisorOptions

Configuration options specific to RSMP Supervisor instances:

```ruby
# Create with defaults
supervisor_options = RSMP::Options::SupervisorOptions.new

# Create with custom configuration
supervisor_options = RSMP::Options::SupervisorOptions.new({
  'port' => 13111,
  'guest' => {
    'sxl' => 'tlc'
  },
  'sites' => {
    'SITE1' => {
      'sxl' => 'tlc'
    }
  }
})

# Convenient accessors
puts supervisor_options.port           # => 13111
puts supervisor_options.ips            # => 'all'
puts supervisor_options.guest_settings # => {"sxl"=>"tlc", ...}
puts supervisor_options.sites_settings # => {"SITE1"=>{"sxl"=>"tlc"}}
```

#### Default Configuration

```yaml
port: 12111
ips: all
guest:
  sxl: tlc
  intervals:
    timer: 1
    watchdog: 1
  timeouts:
    watchdog: 2
    acknowledgement: 2
```

## Using with Site and Supervisor

The configuration system is automatically used by Site and Supervisor classes:

```ruby
# Site with default configuration
site = RSMP::Site.new

# Site with custom configuration
site = RSMP::Site.new(
  site_settings: {
    'site_id' => 'CUSTOM+SITE',
    'supervisors' => [{'ip' => '192.168.1.100', 'port' => 12111}]
  }
)

# Site with configuration from file
site = RSMP::Site.new(site_settings: '/path/to/site_config.yaml')

# Supervisor with custom configuration  
supervisor = RSMP::Supervisor.new(
  supervisor_settings: {
    'port' => 13111,
    'guest' => {'sxl' => 'tlc'}
  }
)
```

## Validation

The configuration system automatically validates:

- **Required fields** - Ensures essential configuration is present
- **Data types** - Validates types match expected schemas  
- **Value ranges** - Checks numeric values are within valid ranges
- **SXL compatibility** - Verifies SXL types and versions are available
- **Core version compatibility** - Ensures core versions are supported
- **Component structure** - Validates component configuration

Validation errors are raised as `RSMP::ConfigurationError` with descriptive messages.

## Factory Method

Use the factory method for convenient creation:

```ruby
# Create SiteOptions
site_options = RSMP::Options.create(:site, config_hash)

# Create SupervisorOptions  
supervisor_options = RSMP::Options.create(:supervisor, config_hash)
```

## Migration from Legacy Configuration

The new configuration system is fully backward compatible. Existing code using the old `handle_site_settings` and `handle_supervisor_settings` methods will continue to work, but the methods are now deprecated.

To migrate:

1. **Replace direct settings access** with option accessors:
   ```ruby
   # Old
   site_id = @site_settings['site_id']
   
   # New  
   site_id = @site_options.site_id
   ```

2. **Use configuration validation** automatically provided by options classes instead of manual validation

3. **Leverage type-safe accessors** instead of hash key access

The legacy `@site_settings` and `@supervisor_settings` hash attributes are still available for backward compatibility.