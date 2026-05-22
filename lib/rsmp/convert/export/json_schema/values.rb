module RSMP
  module Convert
    module Export
      # Converts SXL definitions to JSON Schema files.
      module JSONSchema
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
                         'unevaluatedProperties' => false
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

        # convert yaml values to json schema enum
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

        # convert yaml pattern to json schema
        def self.handle_pattern(item, out)
          out['pattern'] = item['pattern'] if item['pattern']
        end
      end
    end
  end
end
