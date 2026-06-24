module RSMP
  module Convert
    module Export
      # Converts SXL definitions to JSON Schema files.
      module JSONSchema
        # convert a yaml item to json schema
        def self.build_value(item)
          out = {}
          out['description'] = item['description'] if item['description']
          if item['type'] =~ /_list(_as_string)?$/
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
            out['type'] = 'boolean'
          when 'boolean_as_string'
            out['$ref'] = '../defs/definitions.json#/boolean'
          when 'timestamp'
            out['$ref'] = '../defs/definitions.json#/timestamp'
          when 'integer', 'ordinal', 'unit', 'scale', 'long'
            out['type'] = 'integer'
          when 'integer_as_string', 'ordinal_as_string', 'unit_as_string', 'scale_as_string', 'long_as_string'
            out['$ref'] = '../defs/definitions.json#/integer'
          when 'number'
            out['type'] = 'number'
          when 'number_as_string'
            out['type'] = 'string'
            out['pattern'] = '^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?$'
          when 'array' # a json array
            if item['items']
              build_json_array item['items'], out
            else
              out['type'] = 'array'
            end
          when 'object'
            out['type'] = 'object'
          when 'null'
            out['type'] = 'null'
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
          when 'boolean_list', 'boolean_list_as_string'
            out['$ref'] = '../defs/definitions.json#/boolean_list'
          when 'integer_list', 'integer_list_as_string'
            out['$ref'] = '../defs/definitions.json#/integer_list'
          when 'number_list', 'number_list_as_string'
            out['$ref'] = '../defs/definitions.json#/number_list'
          when 'string_list', 'string_list_as_string'
            out['$ref'] = '../defs/definitions.json#/string_list'
          else
            raise "Error: List of #{item['type']} is not supported: #{item.inspect}"
          end

          if item['values']
            value_list = item['values'].keys.join('|')
            out['pattern'] = /(?-mix:^(#{value_list})(?:,(#{value_list}))*$)/
          end

          handle_pattern item, out
        end

        # convert yaml values to json schema enum
        def self.handle_enum(item, out)
          return unless item['values']

          values = enum_keys(item)
          values = stringify_values(values) if string_type? item
          out['enum'] = values
        end

        def self.string_type?(item)
          type = item['type'].to_s
          type == 'string' || type.end_with?('_as_string') || %w[base64 timestamp].include?(type)
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
