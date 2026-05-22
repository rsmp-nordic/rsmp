module RSMP
  module Convert
    module Export
      # Converts SXL definitions to JSON Schema files.
      module JSONSchema
        # convert yaml alarm/status/command item to corresponding json schema
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
      end
    end
  end
end
