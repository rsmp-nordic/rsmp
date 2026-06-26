module RSMP
  # Encodes and decodes SXL argument values for message payloads.
  module MessageSxlCodec
    SXL_ITEM_SHAPES = {
      'StatusResponse' => { kind: :statuses, list: 'sS', code: 'sCI', name: 'n', value: 's' },
      'StatusUpdate' => { kind: :statuses, list: 'sS', code: 'sCI', name: 'n', value: 's' },
      'CommandRequest' => { kind: :commands, list: 'arg', code: 'cCI', name: 'n', value: 'v' },
      'CommandResponse' => { kind: :commands, list: 'rvs', code: 'cCI', name: 'n', value: 'v' },
      'Alarm' => { kind: :alarms, list: 'rvs', code: nil, name: 'n', value: 'v' }
    }.freeze

    def self.included(base)
      base.extend ClassMethods
    end

    def encode_for(schemas)
      transform_sxl_items(schemas, :encode_sxl_value)
      self
    end

    def decode_for(schemas)
      transform_sxl_items(schemas, :decode_sxl_value)
      self
    end

    private

    def transform_sxl_items(schemas, transformer)
      shape = SXL_ITEM_SHAPES[type]
      return unless shape

      resolved = RSMP::Schema.resolve_sxl(@attributes, schemas: schemas)
      return unless resolved

      sxl_type, version = resolved
      Array(@attributes[shape[:list]]).each do |item|
        transform_sxl_item(item, shape, sxl_type, version, transformer)
      end
    end

    def transform_sxl_item(item, shape, sxl_type, version, transformer)
      item_code = shape[:code] ? item[shape[:code]] : @attributes['aCId']
      name = item[shape[:name]]
      return unless item_code && name && item.key?(shape[:value])

      descriptor = RSMP::Schema.sxl_argument_descriptor(sxl_type, version, shape[:kind], item_code, name)
      return unless descriptor

      item[shape[:value]] = self.class.public_send(transformer, item[shape[:value]], descriptor)
    end

    # Class-level value transforms used by Message and command collectors.
    module ClassMethods
      STRING_TYPES = %w[string base64 timestamp].freeze
      INTEGER_AS_STRING_TYPES = %w[integer_as_string long_as_string].freeze

      def encode_sxl_value(value, descriptor)
        return nil if value.nil?

        type = descriptor_type(descriptor)
        return encode_sxl_boolean(value) if type == 'boolean_as_string'
        return encode_sxl_list(value) if list_type?(type)
        return value.is_a?(String) ? value : value.to_s if encode_string_type?(type)
        return encode_sxl_array(value, descriptor) if type == 'array'
        return encode_sxl_object(value, descriptor['properties']) if type == 'object'

        value
      end

      def decode_sxl_value(value, descriptor)
        return nil if value.nil?

        type = descriptor_type(descriptor)
        return decode_sxl_boolean(value) if type == 'boolean_as_string'
        return decode_sxl_integer(value) if INTEGER_AS_STRING_TYPES.include?(type)
        return decode_sxl_number(value) if type == 'number_as_string'
        return decode_sxl_list(value, type) if list_type?(type)
        return decode_sxl_array(value, descriptor) if type == 'array'
        return decode_sxl_object(value, descriptor['properties']) if type == 'object'

        value
      end

      def descriptor_type(descriptor)
        descriptor.is_a?(Hash) ? descriptor['type'] : descriptor.to_s
      end

      def list_type?(type)
        type.match?(/_list(_as_string)?\z/)
      end

      def encode_string_type?(type)
        STRING_TYPES.include?(type) || INTEGER_AS_STRING_TYPES.include?(type) || type == 'number_as_string'
      end

      def encode_sxl_boolean(value)
        case value
        when true
          'True'
        when false
          'False'
        else
          value
        end
      end

      def encode_sxl_list(value)
        return value if value.is_a?(String)
        return encode_sxl_boolean(value).to_s unless value.is_a?(Array)

        value.map { |item| encode_sxl_boolean(item) }.join(',')
      end

      def encode_sxl_array(value, descriptor)
        return value unless value.is_a?(Array)

        items = descriptor['items']
        return value unless items.is_a?(Hash)

        value.map { |item| encode_sxl_object(item, items) }
      end

      def encode_sxl_object(value, properties)
        transform_sxl_object(value, properties, :encode_sxl_value)
      end

      def decode_sxl_boolean(value)
        case value
        when 'True'
          true
        when 'False'
          false
        else
          value
        end
      end

      def decode_sxl_integer(value)
        return value unless value.is_a?(String) && value.match?(/\A[+-]?\d+\z/)

        value.to_i
      end

      def decode_sxl_number(value)
        return value unless value.is_a?(String)

        Float(value)
      rescue ArgumentError
        value
      end

      def decode_sxl_list(value, type)
        items = value.is_a?(String) ? value.split(',') : Array(value)
        descriptor = list_item_descriptor(type)
        items.map { |item| decode_sxl_value(item, descriptor) }
      end

      def list_item_descriptor(type)
        case type
        when /\Aboolean_list/ then 'boolean_as_string'
        when /\Ainteger_list/ then 'integer_as_string'
        when /\Anumber_list/ then 'number_as_string'
        else 'string'
        end
      end

      def decode_sxl_array(value, descriptor)
        return value unless value.is_a?(Array)

        items = descriptor['items']
        return value unless items.is_a?(Hash)

        value.map { |item| decode_sxl_array_item(item, items) }
      end

      def decode_sxl_array_item(item, descriptor)
        descriptor['type'] ? decode_sxl_value(item, descriptor) : decode_sxl_object(item, descriptor)
      end

      def decode_sxl_object(value, properties)
        transform_sxl_object(value, properties, :decode_sxl_value)
      end

      def transform_sxl_object(value, properties, transformer)
        return value unless value.is_a?(Hash) && properties.is_a?(Hash)

        value.each_with_object({}) do |(key, item_value), memo|
          descriptor = properties[key] || properties[key.to_sym]
          memo[key] = descriptor ? public_send(transformer, item_value, descriptor) : item_value
        end
      end
    end
  end
end
