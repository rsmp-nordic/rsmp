# Import SXL from YAML format

require 'yaml'
require 'json'
require 'fileutils'

module RSMP
  module Convert
    module Export
      module JSONSchema

        @@json_options = {
          array_nl: "\n",
          object_nl: "\n",
          indent: '  ',
          space_before: ' ',
          space: ' '
        }

        def self.output_json item
          JSON.generate(item,@@json_options)
        end

        # convert a yaml item to json schema
        def self.build_value item
          out = {}
          out['description'] = item['description'] if item['description']
          if item['type'] =~/_list$/
            handle_string_list item, out
          else
            handle_types item, out
            handle_enum item, out
            handle_pattern item, out
          end
          wrap_refs out
        end

        # convert an item which is not a string-list, to json schema
        def self.handle_types item, out
          case item['type']
          when "string", "base64"
            out["type"] = "string"
          when "boolean"
            out["$ref"] = "../../../core/3.1.2/definitions.json#/boolean"
          when "timestamp"
            out["$ref"] = "../../../core/3.1.2/definitions.json#/timestamp"
          when "integer", "ordinal", "unit", "scale", "long"
            out["$ref"] = "../../../core/3.1.2/definitions.json#/integer"
          when 'array'   # a json array
            build_json_array item['items'], out
          else
            out["type"] = "string"
          end
        end

        # convert an yaml item with type: array to json schema
        def self.build_json_array item, out
          required = item.select { |k,v| v['optional'] != true }.keys.sort
          out.merge!({
            "type" => "array",
            "items" => {
              "type" => "object",
              "required" => required,
              "additionalProperties": false
            }
          })
          out["items"]["properties"] = {}
          item.each_pair do |key,v|
            out["items"]["properties"][key] = build_value(v)
          end
          out
        end

        # with draft-07 and older, using a $ref mean all other properties are ignored.
        # to avoid this we need to use an allOf.
        # this is changed from draft-08, but unfortunately, there is still no Ruby validator for that
        def self.wrap_refs out
          if out.keys.include? '$ref'
            ref = out.delete '$ref'
            { "allOf" => [out,{"$ref"=>ref}]}
          else
            out
          end
        end

        # convert a yaml item with list: true to json schema
        def self.handle_string_list item, out
          case item['type']
          when "boolean_list"
            out["$ref"] = "../../../core/3.1.2/definitions.json#/boolean_list"
          when "integer_list"
            out["$ref"] = "../../../core/3.1.2/definitions.json#/integer_list"
          when "string_list"
            out["$ref"] = "../../../core/3.1.2/definitions.json#/string_list"
          else
            raise "Error: List of #{item['type']} is not supported: #{item.inspect}"
          end

          if item["values"]
            value_list = item["values"].keys.join('|')
            out['pattern'] = /(?-mix:^(#{value_list})(?:,(#{value_list}))*$)/
          end

          puts "Warning: Pattern not support for lists: #{item.inspect}" if item["pattern"]
        end

        # convert yaml values to jsons schema enum
        def self.handle_enum item, out
          if item["values"]
            out["enum"] = case item["values"]
            when Hash
              item["values"].each_pair do |k,v|
                if v=='' or v==nil
                  raise "Error: '#{k}' has empty value in #{item}. (When using a hash to specify 'values', the hash values cannot be empty.)"
                end
              end
              item["values"].keys.sort
            when Array
              item["values"].sort
            else
              raise "Error: Values must be specified as either a Hash or an Array, got #{item["values"].class}"
            end.map do |v|
              if v.is_a?(Integer) || v.is_a?(Float)
                v.to_s
              else
                v
              end
            end
          end
        end

        # convert yaml pattern to jsons schema
        def self.handle_pattern item, out
          out["pattern"] = item["pattern"] if item["pattern"]
        end

        # convert yaml alarm/status/command item to corresponding jsons schema
        def self.build_item item, property_key: 'v'
          unless item['arguments']
            json = {
              "description" => item['description'],
            }
            return json
          end

          json = {
            "description" => item['description'],
            "allOf" => [
              {
               "properties" => { "n" => { "enum" => item['arguments'].keys.sort }},
              },
              {
                "if" =>
                {
                  "required" => ["q"],
                  "properties" => { "q"=> { "enum" => ["undefined","unknown"] }},
                },
                "then" => {},
                "else" => {
                  "allOf" => item['arguments'].map do |key,argument|
                    {
                      "if" => { "required" => ["n"], "properties" => { "n" => { "const" => key }}},
                      "then" => { "properties" => { property_key => build_value(argument) }}
                    }
                  end
                }
              }
            ]
          }

          json
        end

        # convert alarms to json schema
        def self.output_alarms out, items
          list = items.keys.sort.map do |key|
            {
              "if" => { "required" => ["aCId"], "properties" => { "aCId" => { "const" => key }}},
              "then" => { "$ref" => "#{key}.json" }
            }
          end
          json = {
            "properties" => {
              "aCId" => { "enum" => items.keys.sort },
              "rvs" => { "items" => { "allOf" => list } }
            }
          }
          out['alarms/alarms.json'] = output_json json
          items.each_pair { |key,item| output_alarm out, key, item }
        end

        # convert an alarm to json schema
        def self.output_alarm out, key, item
          json = build_item item
          out["alarms/#{key}.json"] = output_json json
        end

        # convert statuses to json schema
        def self.output_statuses out, items
          list = [ { "properties" => { "sCI" => { "enum"=> items.keys.sort }}} ]
          items.keys.sort.each do |key|
            list << {
              "if"=> { "required" => ["sCI"], "properties" => { "sCI"=> { "const"=> key }}},
              "then" => { "$ref" => "#{key}.json" }
            }
          end
          json = { "properties" => { "sS" => { "items" => { "allOf" => list }}}}
          out['statuses/statuses.json'] = output_json json
          items.each_pair { |key,item| output_status out, key, item }
        end

        # convert a status to json schema
        def self.output_status out, key, item
          json = build_item item, property_key: 's'
          out["statuses/#{key}.json"] = output_json json
        end

        # convert commands to json schema
        def self.output_commands out, items
          list = [ { "properties" => { "cCI" => { "enum"=> items.keys.sort }}} ]
          items.keys.sort.each do |key|
            list << {
              "if" => { "required" => ["cCI"], "properties" => { "cCI"=> { "const"=> key }}},
              "then" => { "$ref" => "#{key}.json" }
            }
          end
          json = { "items" => { "allOf" => list }}
          out['commands/commands.json'] = output_json json

          json = { "properties" => { "arg" => { "$ref" => "commands.json" }}}
          out['commands/command_requests.json'] = output_json json

          json = { "properties" => { "rvs" => { "$ref" => "commands.json" }}}
          out['commands/command_responses.json'] = output_json json

          items.each_pair { |key,item| output_command out, key, item }
        end

        # convert a command to json schema
        def self.output_command out, key, item
          json = build_item item
          json["allOf"].first["properties"]['cO'] = { "const" => item['command'] }
          out["commands/#{key}.json"] = output_json json
        end

        # output the json schema root
        def self.output_root out, meta
          json = {
            "name"=> meta['name'],
            "description"=> meta['description'],
            "version"=> meta['version'],
            "allOf" => [
              {
                "if" => { "required" => ["type"], "properties" => { "type" => { "const" => "CommandRequest" }}},
                "then" => { "$ref" => "commands/command_requests.json" }
              },
              {
                "if" => { "required" => ["type"], "properties" => { "type" => { "const" => "CommandResponse" }}},
                "then" => { "$ref" => "commands/command_responses.json" }
              },
              {
                "if" => { "required" => ["type"], "properties" => { "type" => { "enum" => ["StatusRequest","StatusResponse","StatusSubscribe","StatusUnsubscribe","StatusUpdate"] }}},
                "then" => { "$ref" => "statuses/statuses.json" }
              },
              {
                "if" => { "required" => ["type"], "properties" => { "type" => { "const" => "Alarm" }}},
                "then" => { "$ref" => "alarms/alarms.json" }
              }
            ]
          }
          out["rsmp.json"] = output_json json
        end

        # generate the json schema from a string containing yaml
        def self.generate sxl
          out = {}
          output_root out, sxl[:meta]
          output_alarms out, sxl[:alarms]
          output_statuses out, sxl[:statuses]
          output_commands out, sxl[:commands]
          out
        end

        # convert yaml to json schema and write files to a folder
        def self.write sxl, folder
          out = generate sxl
          out.each_pair do |relative_path,str|
            path = File.join(folder, relative_path)
            FileUtils.mkdir_p File.dirname(path)      # create folders if needed
            file = File.open(path, 'w+')      # w+ means truncate or create new file
            file.puts str
          end
        end
      end
    end
  end
end