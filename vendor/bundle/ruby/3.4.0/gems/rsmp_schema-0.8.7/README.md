# About
JSON Schema for RSMP messages. The schema can be used to automatically validate RSMP messages.

The schema so far covers the core specifiation and the SXL for Trafic Light Controllers:
https://github.com/rsmp-nordic/rsmp_core
https://github.com/rsmp-nordic/rsmp_sxl_traffic_lights

More about JSON Schema:
https://json-schema.org/

## Schema organisation
The schema consists of a core schema shared by all equipment types, and an SXL schema for each supported equipment type. At the only SXL supported is for Traffic Light Controllers. An SXL defines massages specific to a particular type of equipment, but they all rely on the core part of the RSMP specification.

Both core and SXL schemas exist in different version, for validation agaist a particular version of the spec.

For example, to validate against the SXL for Trafic Light Controllers (TLCs), version 1.0.15, use the file schemas/tcl/1.0.15/rsmp.json.

Depending on the message type, relevant JSON Schema elements will be included to validate the detailed parameters, arguments, etc.

For example, validating a CommandRequest M0001 message will include these parts:

```
rsmp.json
  commands.json
    M0001.json
```

## Usage
The JSON Schema can be used from any language that provides a suitable JSON Schema validation library.

For example, to validate a JSON message with Ruby using the json_schemer gem:

```ruby
require 'json_schemer'

message = {
  "mType" => "rSMsg",
  "mId" => "4173c2c8-a933-43cb-9425-66d4613731ed",
  "type" => "CommandRequest",
  "siteId" => [
    { "sId" => "RN+SI0001" }
  ],
  "cId" => "O+14439=481WA001",
  "arg" => [
    {
      "cCI" => "M0001",
      "n" => "status",
      "cO" => "setValue",
      "v" => "YellowFlash"
    }
  ]
}

# try validating a message against our schema
schema = Pathname.new('schemas/tlc/1.1.0/rsmp.json')
schemer = JSONSchemer.schema(schema)
puts schemer.valid? message     # => true
```

## RSpec tests
The reposity includes RSpec test written in Ruby that checks the schema, by testing the result of validating a set of RSMP messages using the json_schemer gem.

To run the tests, you need Ruby installed. Then run bundler to ensure you have rspec. Then run use the rspec command to run tests:

```
$ bundle              # install gems
$ bundle exec rspec   # run rspec tests
```

## Schema maintenance
The SXL JSON Schemas are generated automatically from their corresponding YAML source, and should therefore not be edited by hand. Instead, edit the YAML source and regenerate the schema files.

The core schemas has no YAML sources and are maintained by hand.
