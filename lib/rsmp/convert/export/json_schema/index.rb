module RSMP
  module Convert
    module Export
      # Converts SXL definitions to JSON Schema files.
      module JSONSchema
        def self.output_sxl_index(out, sxl)
          out['sxl_index.json'] = output_json({
                                                'meta' => sxl[:meta],
                                                'statuses' => index_items(sxl[:statuses], legacy_types: legacy_types?(sxl)),
                                                'commands' => index_items(sxl[:commands], legacy_types: legacy_types?(sxl)),
                                                'alarms' => index_items(sxl[:alarms], legacy_types: legacy_types?(sxl))
                                              })
        end

        def self.legacy_types?(sxl)
          Gem::Version.new(minimum_core_version(sxl).to_s) < Gem::Version.new('3.3.0')
        end

        def self.index_items(items, legacy_types:)
          items.keys.sort.to_h do |key|
            [key, index_item(items[key], legacy_types: legacy_types)]
          end
        end

        def self.index_item(item, legacy_types:)
          arguments = item['arguments'] || {}
          entry = {}
          required = typed_arguments(arguments.reject { |_name, argument| argument['optional'] == true },
                                     legacy_types: legacy_types)
          optional = typed_arguments(arguments.select { |_name, argument| argument['optional'] == true },
                                     legacy_types: legacy_types)
          entry['required'] = required unless required.empty?
          entry['optional'] = optional unless optional.empty?
          entry
        end

        def self.typed_arguments(arguments, legacy_types:)
          arguments.keys.sort.to_h do |name|
            [name, argument_type_descriptor(arguments[name], legacy_types: legacy_types)]
          end
        end

        def self.argument_type_descriptor(argument, legacy_types:)
          type = argument['type']
          case type
          when 'array'
            argument_array_descriptor(argument, legacy_types: legacy_types)
          when 'object'
            argument_object_descriptor(argument, legacy_types: legacy_types)
          else
            legacy_types ? legacy_index_type(type) : type
          end
        end

        def self.legacy_index_type(type)
          case type
          when 'boolean'
            'boolean_as_string'
          when 'integer'
            'integer_as_string'
          when 'long'
            'long_as_string'
          when 'number'
            'number_as_string'
          else
            type
          end
        end

        def self.argument_array_descriptor(argument, legacy_types:)
          descriptor = { 'type' => argument['type'] }
          descriptor['items'] = typed_arguments(argument['items'], legacy_types: legacy_types) if argument['items'].is_a?(Hash)
          descriptor
        end

        def self.argument_object_descriptor(argument, legacy_types:)
          descriptor = { 'type' => argument['type'] }
          properties = argument['properties'] || argument['items']
          descriptor['properties'] = typed_arguments(properties, legacy_types: legacy_types) if properties.is_a?(Hash)
          descriptor
        end
      end
    end
  end
end
