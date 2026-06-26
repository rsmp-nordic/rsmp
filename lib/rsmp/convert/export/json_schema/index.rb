module RSMP
  module Convert
    module Export
      # Converts SXL definitions to JSON Schema files.
      module JSONSchema
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
            [key, index_item(items[key])]
          end
        end

        def self.index_item(item)
          arguments = item['arguments'] || {}
          entry = {}
          required = typed_arguments(arguments.reject { |_name, argument| argument['optional'] == true })
          optional = typed_arguments(arguments.select { |_name, argument| argument['optional'] == true })
          entry['required'] = required unless required.empty?
          entry['optional'] = optional unless optional.empty?
          entry
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
            argument_array_descriptor(argument)
          when 'object'
            argument_object_descriptor(argument)
          else
            type
          end
        end

        def self.argument_array_descriptor(argument)
          descriptor = { 'type' => argument['type'] }
          descriptor['items'] = typed_arguments(argument['items']) if argument['items'].is_a?(Hash)
          descriptor
        end

        def self.argument_object_descriptor(argument)
          descriptor = { 'type' => argument['type'] }
          properties = argument['properties'] || argument['items']
          descriptor['properties'] = typed_arguments(properties) if properties.is_a?(Hash)
          descriptor
        end
      end
    end
  end
end
