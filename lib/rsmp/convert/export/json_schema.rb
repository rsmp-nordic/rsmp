# Export SXL to JSON Schema format

require 'yaml'
require 'json'
require 'fileutils'

module RSMP
  module Convert
    # Handles exporting SXL definitions.
    module Export
      # Converts SXL definitions to JSON Schema files.
      module JSONSchema
        JSON_OPTIONS = {
          array_nl: "\n",
          object_nl: "\n",
          indent: '  ',
          space_before: ' ',
          space: ' '
        }.freeze

        def self.output_json(item)
          JSON.generate(item, JSON_OPTIONS)
        end

        # convert a yaml item to json schema
        def self.build_value(item)
          out = {}
          out['description'] = item['description'] if item['description']
          if item['type'] =~ /_list$/
            handle_string_list item, out
          else
            handle_types item, out
            handle_enum item, out
            handle_pattern item, out
          end
          wrap_refs out
        end

        # convert an item which is not a string-list, to json schema
        def self.handle_types(item, out)
          case item['type']
          when 'boolean'
            out['$ref'] = '../defs/definitions.json#/boolean'
          when 'timestamp'
            out['$ref'] = '../defs/definitions.json#/timestamp'
          when 'integer', 'ordinal', 'unit', 'scale', 'long'
            out['$ref'] = '../defs/definitions.json#/integer'
          when 'array' # a json array
            build_json_array item['items'], out
          else # string, base64, and any unknown types
            out['type'] = 'string'
          end
        end

        # convert an yaml item with type: array to json schema
        def self.build_json_array(item, out)
          required = item.reject { |_k, v| v['optional'] == true }.keys.sort
          out.merge!({
                       'type' => 'array',
                       'items' => {
                         'type' => 'object',
                         'required' => required,
                         'unevaluatedProperties' => false # Modern alternative to additionalProperties
                       }
                     })
          out['items']['properties'] = {}
          item.each_pair do |key, v|
            out['items']['properties'][key] = build_value(v)
          end
          out
        end

        # JSON Schema 2020-12 allows combining $ref with other properties directly
        def self.wrap_refs(out)
          # No wrapping needed with modern JSON Schema
          out
        end

        # convert a yaml item with list: true to json schema
        def self.handle_string_list(item, out)
          case item['type']
          when 'boolean_list'
            out['$ref'] = '../defs/definitions.json#/boolean_list'
          when 'integer_list'
            out['$ref'] = '../defs/definitions.json#/integer_list'
          when 'string_list'
            out['$ref'] = '../defs/definitions.json#/string_list'
          else
            raise "Error: List of #{item['type']} is not supported: #{item.inspect}"
          end

          if item['values']
            value_list = item['values'].keys.join('|')
            out['pattern'] = /(?-mix:^(#{value_list})(?:,(#{value_list}))*$)/
          end

          puts "Warning: Pattern not support for lists: #{item.inspect}" if item['pattern']
        end

        # convert yaml values to jsons schema enum
        def self.handle_enum(item, out)
          return unless item['values']

          out['enum'] = stringify_values(enum_keys(item))
        end

        def self.enum_keys(item)
          case item['values']
          when Hash
            validate_hash_values! item
            item['values'].keys.sort
          when Array
            item['values'].sort
          else
            raise 'Error: Values must be specified as either a Hash or an Array, ' \
                  "got #{item['values'].class}"
          end
        end

        def self.validate_hash_values!(item)
          item['values'].each_pair do |k, v|
            next unless ['', nil].include?(v)

            raise "Error: '#{k}' has empty value in #{item}. " \
                  '(When using a hash to specify \'values\', the hash values cannot be empty.)'
          end
        end

        def self.stringify_values(values)
          values.map { |v| v.is_a?(Integer) || v.is_a?(Float) ? v.to_s : v }
        end

        # convert yaml pattern to jsons schema
        def self.handle_pattern(item, out)
          out['pattern'] = item['pattern'] if item['pattern']
        end

        # convert yaml alarm/status/command item to corresponding jsons schema
        def self.build_item(item, property_key: 'v')
          arguments = item['arguments']
          return simple_item(item) unless arguments

          property_key == 's' ? build_status_item(item, arguments) : build_default_item(item, arguments, property_key)
        end

        def self.simple_item(item)
          {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'description' => item['description']
          }
        end

        def self.build_status_item(item, arguments)
          branches = arguments.map do |key, argument|
            {
              'if' => { 'properties' => { 'n' => { 'const' => key } } },
              'then' => { 'properties' => { 's' => build_value(argument) } }
            }
          end
          {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'description' => item['description'],
            'properties' => { 'n' => { 'enum' => arguments.keys.sort } },
            'if' => { '$ref' => '../defs/guards.json#/$defs/q_unknown_or_undefined' },
            'then' => {},
            'else' => { 'allOf' => branches }
          }
        end

        def self.build_default_item(item, arguments, property_key)
          rules = arguments.map do |key, argument|
            {
              'if' => { 'properties' => { 'n' => { 'const' => key } } },
              'then' => { 'properties' => { property_key => build_value(argument) } }
            }
          end
          {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'description' => item['description'],
            'properties' => { 'n' => { 'enum' => arguments.keys.sort } },
            'allOf' => rules
          }
        end

        # convert alarms to json schema
        def self.output_alarms(out, items)
          list = items.keys.sort.map do |key|
            {
              'if' => { 'required' => ['aCId'], 'properties' => { 'aCId' => { 'const' => key } } },
              'then' => { '$ref' => "#{key}.json" }
            }
          end
          json = {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'properties' => {
              'aCId' => { 'enum' => items.keys.sort },
              'rvs' => { 'items' => { 'allOf' => list } }
            }
          }
          out['alarms/alarms.json'] = output_json json
          items.each_pair { |key, item| output_alarm out, key, item }
        end

        # convert an alarm to json schema
        def self.output_alarm(out, key, item)
          json = build_item item
          out["alarms/#{key}.json"] = output_json json
        end

        # convert statuses to json schema
        def self.output_statuses(out, items)
          # ensure shared guard is written (relative to version folder)
          out['defs/guards.json'] ||= output_json({
                                                    '$schema' => 'https://json-schema.org/draft/2020-12/schema',
                                                    '$defs' => {
                                                      'q_unknown_or_undefined' => {
                                                        'allOf' => [
                                                          { 'required' => ['q'] },
                                                          { 'properties' => { 'q' => { 'enum' => %w[undefined
                                                                                                    unknown] } } }
                                                        ]
                                                      }
                                                    }
                                                  })

          list = [{ 'properties' => { 'sCI' => { 'enum' => items.keys.sort } } }]
          items.keys.sort.each do |key|
            list << {
              'if' => { 'required' => ['sCI'], 'properties' => { 'sCI' => { 'const' => key } } },
              'then' => { '$ref' => "#{key}.json" }
            }
          end
          json = {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'properties' => { 'sS' => { 'items' => { 'allOf' => list } } }
          }
          out['statuses/statuses.json'] = output_json json
          items.each_pair { |key, item| output_status out, key, item }
        end

        # convert a status to json schema
        def self.output_status(out, key, item)
          json = build_item item, property_key: 's'
          out["statuses/#{key}.json"] = output_json json
        end

        # convert commands to json schema
        def self.output_commands(out, items)
          list = [{ 'properties' => { 'cCI' => { 'enum' => items.keys.sort } } }]
          items.keys.sort.each do |key|
            list << {
              'if' => { 'required' => ['cCI'], 'properties' => { 'cCI' => { 'const' => key } } },
              'then' => { '$ref' => "#{key}.json" }
            }
          end
          json = {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'items' => { 'allOf' => list }
          }
          out['commands/commands.json'] = output_json json

          json = {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'properties' => { 'arg' => { '$ref' => 'commands.json' } }
          }
          out['commands/command_requests.json'] = output_json json

          json = {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'properties' => { 'rvs' => { '$ref' => 'commands.json' } }
          }
          out['commands/command_responses.json'] = output_json json

          items.each_pair { |key, item| output_command out, key, item }
        end

        # convert a command to json schema
        def self.output_command(out, key, item)
          json = build_item item
          # Always add the command operation (cO) constraint at the top-level properties
          json['properties'] ||= {}
          json['properties']['cO'] = { 'const' => item['command'] }

          out["commands/#{key}.json"] = output_json json
        end

        # output the json schema root
        def self.output_root(out, meta)
          json = {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'name' => meta['name'],
            'description' => meta['description'],
            'version' => meta['version'],
            'allOf' => root_type_rules
          }
          out['rsmp.json'] = output_json json
        end

        def self.root_type_rules
          [
            {
              'if' => { 'required' => ['type'], 'properties' => { 'type' => { 'const' => 'CommandRequest' } } },
              'then' => { '$ref' => 'commands/command_requests.json' }
            },
            {
              'if' => { 'required' => ['type'], 'properties' => { 'type' => { 'const' => 'CommandResponse' } } },
              'then' => { '$ref' => 'commands/command_responses.json' }
            },
            {
              'if' => {
                'required' => ['type'],
                'properties' => {
                  'type' => { 'enum' => %w[StatusRequest StatusResponse StatusSubscribe StatusUnsubscribe
                                           StatusUpdate] }
                }
              },
              'then' => { '$ref' => 'statuses/statuses.json' }
            },
            {
              'if' => { 'required' => ['type'], 'properties' => { 'type' => { 'const' => 'Alarm' } } },
              'then' => { '$ref' => 'alarms/alarms.json' }
            }
          ]
        end

        # generate the json schema from a string containing yaml
        def self.generate(sxl)
          out = {}
          output_root out, sxl[:meta]
          output_alarms out, sxl[:alarms]
          output_statuses out, sxl[:statuses]
          output_commands out, sxl[:commands]
          out
        end

        # Default path to definitions.json bundled with the gem's core schemas
        DEFINITIONS_SOURCE = File.expand_path('../../../../schemas/core/3.1.2/definitions.json', __dir__)

        # convert yaml to json schema and write files to a folder
        def self.write(sxl, folder)
          out = generate sxl
          out.each_pair do |relative_path, str|
            path = File.join(folder, relative_path)
            FileUtils.mkdir_p File.dirname(path)
            File.open(path, 'w+') { |file| file.puts str }
          end
          # Copy definitions.json so each version folder is self-contained
          defs_dest = File.join(folder, 'defs', 'definitions.json')
          FileUtils.mkdir_p File.dirname(defs_dest)
          FileUtils.cp DEFINITIONS_SOURCE, defs_dest if File.exist?(DEFINITIONS_SOURCE)
        end
      end
    end
  end
end
