# Import SXL from YAML format

require 'yaml'
require 'json'
require 'fileutils'

module RSMP
  module Convert
    module Export
      module JSONSchema
        module ValueBuilders
          def build_value(item)
            out = { 'description' => item['description'] }.compact
            item['list'] ? build_list_value(out, item) : build_single_value(out, item)
            out
          end

          def build_item(item, property_key: 'v')
            json = base_item_schema(item)
            return json unless item['arguments']

            json['allOf'].first['properties'] = { 'n' => { 'enum' => item['arguments'].keys.sort } }
            item['arguments'].each_pair do |key, argument|
              json['allOf'] << argument_schema(key, argument, property_key)
            end
            json
          end

          private

          def build_list_value(out, item)
            out['$ref'] = list_reference(item)
            assign_list_pattern(out, item)
            puts "Warning: Pattern not support for lists: #{item.inspect}" if item['pattern']
          end

          def list_reference(item)
            case item['type']
            when 'boolean'
              '../../../core/3.1.1/definitions.json#/boolean_list'
            when 'integer', 'ordinal', 'unit', 'scale', 'long'
              '../../../core/3.1.1/definitions.json#/integer_list'
            else
              raise "Error: List of #{item['type']} is not supported: #{item.inspect}"
            end
          end

          def assign_list_pattern(out, item)
            return unless item['values']

            value_list = item['values'].keys.join('|')
            out['pattern'] = /(?-mix:^(#{value_list})(?:,(#{value_list}))*$)/
          end

          def build_single_value(out, item)
            out.merge!(single_value_reference(item))
            out['enum'] = item['values'].keys.sort if item['values']
            out['pattern'] = item['pattern'] if item['pattern']
          end

          def single_value_reference(item)
            case item['type']
            when 'boolean'
              { '$ref' => '../../../core/3.1.1/definitions.json#/boolean' }
            when 'timestamp'
              { '$ref' => '../../../core/3.1.1/definitions.json#/timestamp' }
            when 'integer', 'ordinal', 'unit', 'scale', 'long'
              { '$ref' => '../../../core/3.1.1/definitions.json#/integer' }
            else
              { 'type' => 'string' }
            end
          end

          def base_item_schema(item)
            { 'allOf' => [{ 'description' => item['description'] }] }
          end

          def argument_schema(key, argument, property_key)
            {
              'if' => { 'required' => ['n'], 'properties' => { 'n' => { 'const' => key } } },
              'then' => { 'properties' => { property_key => build_value(argument) } }
            }
          end
        end
      end
    end
  end
end

module RSMP
  module Convert
    module Export
      module JSONSchema
        module SchemaOutputs
          STATUS_TYPES = %w[StatusRequest StatusResponse StatusSubscribe StatusUnsubscribe StatusUpdate].freeze

          def output_alarms(out, items)
            out['alarms/alarms.json'] = output_json(alarms_schema(items))
            items.each_pair { |key, item| output_alarm(out, key, item) }
          end

          def output_alarm(out, key, item)
            out["alarms/#{key}.json"] = output_json(build_item(item))
          end

          def output_statuses(out, items)
            out['statuses/statuses.json'] = output_json(status_schema(items))
            items.each_pair { |key, item| output_status(out, key, item) }
          end

          def output_status(out, key, item)
            out["statuses/#{key}.json"] = output_json(build_item(item, property_key: 's'))
          end

          def output_commands(out, items)
            out['commands/commands.json'] = output_json(command_items_schema(items))
            out['commands/command_requests.json'] = output_json(command_request_schema)
            out['commands/command_responses.json'] = output_json(command_response_schema)
            items.each_pair { |key, item| output_command(out, key, item) }
          end

          def output_command(out, key, item)
            json = build_item(item)
            json['allOf'].first['properties']['cO'] = { 'const' => item['command'] }
            out["commands/#{key}.json"] = output_json(json)
          end

          def output_root(out, meta)
            out['sxl.json'] = output_json(root_schema(meta))
          end

          private

          def alarms_schema(items)
            {
              'properties' => {
                'aCId' => { 'enum' => items.keys.sort },
                'rvs' => { 'items' => { 'allOf' => alarm_clauses(items) } }
              }
            }
          end

          def alarm_clauses(items)
            items.keys.sort.map { |key| schema_clause('aCId', key, "#{key}.json") }
          end

          def status_schema(items)
            {
              'properties' => {
                'sS' => { 'items' => { 'allOf' => status_clauses(items) } }
              }
            }
          end

          def status_clauses(items)
            [enum_clause('sCI', items.keys.sort)] + items.keys.sort.map do |key|
              schema_clause('sCI', key, "#{key}.json")
            end
          end

          def command_items_schema(items)
            { 'items' => { 'allOf' => command_clauses(items) } }
          end

          def command_clauses(items)
            [enum_clause('cCI', items.keys.sort)] + items.keys.sort.map do |key|
              schema_clause('cCI', key, "#{key}.json")
            end
          end

          def command_request_schema
            { 'properties' => { 'arg' => { '$ref' => 'commands.json' } } }
          end

          def command_response_schema
            { 'properties' => { 'rvs' => { '$ref' => 'commands.json' } } }
          end

          def root_schema(meta)
            {
              'name' => meta['name'],
              'description' => meta['description'],
              'version' => meta['version'],
              'allOf' => root_clauses
            }
          end

          def root_clauses
            [
              schema_clause('type', 'CommandRequest', 'commands/command_requests.json'),
              schema_clause('type', 'CommandResponse', 'commands/command_responses.json'),
              schema_clause('type', STATUS_TYPES, 'statuses/statuses.json'),
              schema_clause('type', 'Alarm', 'alarms/alarms.json')
            ]
          end

          def schema_clause(property, expected, ref)
            {
              'if' => {
                'required' => [property],
                'properties' => { property => schema_expectation(expected) }
              },
              'then' => { '$ref' => ref }
            }
          end

          def enum_clause(property, values)
            { 'properties' => { property => { 'enum' => values } } }
          end

          def schema_expectation(expected)
            expected.is_a?(Array) ? { 'enum' => expected } : { 'const' => expected }
          end
        end
      end
    end
  end
end

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

        extend ValueBuilders
        extend SchemaOutputs

        def self.output_json(item)
          JSON.generate(item, JSON_OPTIONS)
        end

        def self.generate(sxl)
          out = {}
          output_root(out, sxl[:meta])
          output_alarms(out, sxl[:alarms])
          output_statuses(out, sxl[:statuses])
          output_commands(out, sxl[:commands])
          out
        end

        def self.write(sxl, folder)
          generate(sxl).each_pair do |relative_path, str|
            path = File.join(folder, relative_path)
            FileUtils.mkdir_p File.dirname(path)
            File.write(path, "#{str}\n")
          end
        end
      end
    end
  end
end
