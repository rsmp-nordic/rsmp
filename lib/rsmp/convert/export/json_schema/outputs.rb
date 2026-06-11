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
          items.keys.sort.each_with_object({}) do |key, index|
            index[key] = {
              'arguments' => (items[key]['arguments'] || {}).keys.sort
            }
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
