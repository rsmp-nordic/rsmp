# Import SXL from YAML format

require 'yaml'
require 'json'
require 'fileutils'

module RSMP
  module Convert
    module Export
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

        def self.build_value(item)
          out = {}

          out['description'] = item['description'] if item['description']

          if item['list']
            case item['type']
            when 'boolean'
              out['$ref'] = '../../../core/3.1.1/definitions.json#/boolean_list'
            when 'integer', 'ordinal', 'unit', 'scale', 'long'
              out['$ref'] = '../../../core/3.1.1/definitions.json#/integer_list'
            else
              raise "Error: List of #{item['type']} is not supported: #{item.inspect}"
            end

            if item['values']
              value_list = item['values'].keys.join('|')
              out['pattern'] = /(?-mix:^(#{value_list})(?:,(#{value_list}))*$)/
            end

            puts "Warning: Pattern not support for lists: #{item.inspect}" if item['pattern']
          else
            case item['type']
            when 'string', 'base64'
              out['type'] = 'string'
            when 'boolean'
              out['$ref'] = '../../../core/3.1.1/definitions.json#/boolean'
            when 'timestamp'
              out['$ref'] = '../../../core/3.1.1/definitions.json#/timestamp'
            when 'integer', 'ordinal', 'unit', 'scale', 'long'
              out['$ref'] = '../../../core/3.1.1/definitions.json#/integer'
            else
              out['type'] = 'string'
            end

            out['enum'] = item['values'].keys.sort if item['values']

            out['pattern'] = item['pattern'] if item['pattern']
          end

          out
        end

        def self.build_item(item, property_key: 'v')
          json = { 'allOf' => [{ 'description' => item['description'] }] }
          if item['arguments']
            json['allOf'].first['properties'] = { 'n' => { 'enum' => item['arguments'].keys.sort } }
            item['arguments'].each_pair do |key, argument|
              json['allOf'] << {
                'if' => { 'required' => ['n'], 'properties' => { 'n' => { 'const' => key } } },
                'then' => { 'properties' => { property_key => build_value(argument) } }
              }
            end
          end
          json
        end

        def self.output_alarms(out, items)
          list = items.keys.sort.map do |key|
            {
              'if' => { 'required' => ['aCId'], 'properties' => { 'aCId' => { 'const' => key } } },
              'then' => { '$ref' => "#{key}.json" }
            }
          end
          json = {
            'properties' => {
              'aCId' => { 'enum' => items.keys.sort },
              'rvs' => { 'items' => { 'allOf' => list } }
            }
          }
          out['alarms/alarms.json'] = output_json json
          items.each_pair { |key, item| output_alarm out, key, item }
        end

        def self.output_alarm(out, key, item)
          json = build_item item
          out["alarms/#{key}.json"] = output_json json
        end

        def self.output_statuses(out, items)
          list = [{ 'properties' => { 'sCI' => { 'enum' => items.keys.sort } } }]
          items.keys.sort.each do |key|
            list << {
              'if' => { 'required' => ['sCI'], 'properties' => { 'sCI' => { 'const' => key } } },
              'then' => { '$ref' => "#{key}.json" }
            }
          end
          json = { 'properties' => { 'sS' => { 'items' => { 'allOf' => list } } } }
          out['statuses/statuses.json'] = output_json json
          items.each_pair { |key, item| output_status out, key, item }
        end

        def self.output_status(out, key, item)
          json = build_item item, property_key: 's'
          out["statuses/#{key}.json"] = output_json json
        end

        def self.output_commands(out, items)
          list = [{ 'properties' => { 'cCI' => { 'enum' => items.keys.sort } } }]
          items.keys.sort.each do |key|
            list << {
              'if' => { 'required' => ['cCI'], 'properties' => { 'cCI' => { 'const' => key } } },
              'then' => { '$ref' => "#{key}.json" }
            }
          end
          json = { 'items' => { 'allOf' => list } }
          out['commands/commands.json'] = output_json json

          json = { 'properties' => { 'arg' => { '$ref' => 'commands.json' } } }
          out['commands/command_requests.json'] = output_json json

          json = { 'properties' => { 'rvs' => { '$ref' => 'commands.json' } } }
          out['commands/command_responses.json'] = output_json json

          items.each_pair { |key, item| output_command out, key, item }
        end

        def self.output_command(out, key, item)
          json = build_item item
          json['allOf'].first['properties']['cO'] = { 'const' => item['command'] }
          out["commands/#{key}.json"] = output_json json
        end

        def self.output_root(out, meta)
          json = {
            'name' => meta['name'],
            'description' => meta['description'],
            'version' => meta['version'],
            'allOf' => [
              {
                'if' => { 'required' => ['type'], 'properties' => { 'type' => { 'const' => 'CommandRequest' } } },
                'then' => { '$ref' => 'commands/command_requests.json' }
              },
              {
                'if' => { 'required' => ['type'], 'properties' => { 'type' => { 'const' => 'CommandResponse' } } },
                'then' => { '$ref' => 'commands/command_responses.json' }
              },
              {
                'if' => { 'required' => ['type'],
                          'properties' => { 'type' => { 'enum' => %w[StatusRequest StatusResponse StatusSubscribe StatusUnsubscribe
                                                                     StatusUpdate] } } },
                'then' => { '$ref' => 'statuses/statuses.json' }
              },
              {
                'if' => { 'required' => ['type'], 'properties' => { 'type' => { 'const' => 'Alarm' } } },
                'then' => { '$ref' => 'alarms/alarms.json' }
              }
            ]
          }
          out['sxl.json'] = output_json json
        end

        def self.generate(sxl)
          out = {}
          output_root out, sxl[:meta]
          output_alarms out, sxl[:alarms]
          output_statuses out, sxl[:statuses]
          output_commands out, sxl[:commands]
          out
        end

        def self.write(sxl, folder)
          out = generate sxl
          out.each_pair do |relative_path, str|
            path = File.join(folder, relative_path)
            FileUtils.mkdir_p File.dirname(path) # create folders if needed
            file = File.open(path, 'w+') # w+ means truncate or create new file
            file.puts str
          end
        end
      end
    end
  end
end
