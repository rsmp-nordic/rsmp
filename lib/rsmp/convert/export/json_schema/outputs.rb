module RSMP
  module Convert
    module Export
      # Converts SXL definitions to JSON Schema files.
      module JSONSchema
        GUARDS_JSON = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          '$defs' => {
            'q_unknown_or_undefined' => {
              'allOf' => [
                { 'required' => ['q'] },
                { 'properties' => { 'q' => { 'enum' => %w[undefined unknown] } } }
              ]
            },
            'age_unknown_or_undefined' => {
              'allOf' => [
                { 'required' => ['age'] },
                { 'properties' => { 'age' => { 'enum' => %w[undefined unknown] } } }
              ]
            }
          }
        }.freeze

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
          out['defs/guards.json'] ||= output_json(GUARDS_JSON)

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
          out['defs/guards.json'] ||= output_json(GUARDS_JSON)

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
            'properties' => { 'arg' => command_request_arg_schema(items) }
          }
          out['commands/command_requests.json'] = output_json json

          json = {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'properties' => { 'rvs' => { '$ref' => 'commands.json' } }
          }
          out['commands/command_responses.json'] = output_json json

          items.each_pair { |key, item| output_command out, key, item }
        end

        def self.command_request_arg_schema(items)
          schema = { '$ref' => 'commands.json' }
          required_rules = command_required_argument_rules(items)
          return schema if required_rules.empty?

          { 'allOf' => [schema] + required_rules }
        end

        def self.command_required_argument_rules(items)
          items.keys.sort.filter_map do |key|
            required = required_argument_names(items[key])
            next if required.empty?

            {
              'if' => {
                'contains' => {
                  'required' => ['cCI'],
                  'properties' => { 'cCI' => { 'const' => key } }
                }
              },
              'then' => {
                'allOf' => required.map { |name| command_argument_contains_rule(key, name) }
              }
            }
          end
        end

        def self.command_argument_contains_rule(command_code, name)
          {
            'contains' => {
              'required' => %w[cCI n],
              'properties' => {
                'cCI' => { 'const' => command_code },
                'n' => { 'const' => name }
              }
            }
          }
        end

        def self.required_argument_names(item)
          (item['arguments'] || {}).reject { |_name, argument| argument['optional'] == true }.keys.sort
        end

        # convert a command to json schema
        def self.output_command(out, key, item)
          json = build_item item
          json['properties'] ||= {}
          json['properties']['cO'] = { 'const' => item['command'] }
          out["commands/#{key}.json"] = output_json json
        end

        def self.output_sxl_index(out, sxl)
          out['sxl_index.json'] = output_json({
                                                'meta' => sxl[:meta],
                                                'statuses' => index_items(sxl[:statuses]),
                                                'commands' => index_items(sxl[:commands]),
                                                'alarms' => index_items(sxl[:alarms])
                                              })
        end

        def self.index_items(items)
          items.keys.sort.to_h do |key|
            arguments = items[key]['arguments'] || {}
            entry = {}
            required = typed_arguments(arguments.reject { |_name, argument| argument['optional'] == true })
            optional = typed_arguments(arguments.select { |_name, argument| argument['optional'] == true })
            entry['required'] = required unless required.empty?
            entry['optional'] = optional unless optional.empty?
            [key, entry]
          end
        end

        def self.typed_arguments(arguments)
          arguments.keys.sort.to_h do |name|
            [name, argument_type_descriptor(arguments[name])]
          end
        end

        def self.argument_type_descriptor(argument)
          type = argument['type']
          case type
          when 'array'
            descriptor = { 'type' => type }
            descriptor['items'] = typed_arguments(argument['items']) if argument['items'].is_a?(Hash)
            descriptor
          when 'object'
            descriptor = { 'type' => type }
            properties = argument['properties'] || argument['items']
            descriptor['properties'] = typed_arguments(properties) if properties.is_a?(Hash)
            descriptor
          else
            type
          end
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
          json['prefix'] = meta['prefix'] if meta['prefix']
          json['minimum_core_version'] = meta['minimum_core_version'] if meta['minimum_core_version']
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
      end
    end
  end
end
