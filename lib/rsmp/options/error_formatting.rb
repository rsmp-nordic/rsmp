module RSMP
  # Formats JSON schema validation errors for user-facing configuration messages.
  module OptionsErrorFormatting
    private

    def format_error(error)
      pointer = error_pointer(error)
      details = error_details(error)
      type_hint = error_type_hint(error)
      schema_suffix = schema_pointer_suffix(error)

      "#{pointer}: #{details}#{type_hint}#{schema_suffix}"
    end

    def error_pointer(error)
      pointer = error['data_pointer'] || error['instanceLocation'] || error['dataPath']
      pointer = pointer.to_s
      pointer.empty? ? '/' : pointer
    end

    def error_details(error)
      details = error['message'] || error['error']
      details ||= begin
        type = error['type'] || error['keyword']
        extra = error['details']
        [type, extra].compact.join(' ')
      end
      details.to_s
    end

    def error_type_hint(error)
      expected = expected_type(error['schema'])
      actual = describe_type(error['data'])
      return '' unless expected && actual

      " (expected #{expected}, got #{actual})"
    end

    def schema_pointer_suffix(error)
      schema_pointer = error['schema_pointer'] || error['schemaLocation'] || error['keywordLocation']
      schema_pointer = schema_pointer.to_s
      schema_pointer.empty? ? '' : " (schema #{schema_pointer})"
    end

    def expected_type(schema)
      return unless schema.is_a?(Hash)

      type = schema['type']
      return format_type(type) if type

      types = []
      %w[oneOf anyOf].each do |key|
        next unless schema[key].is_a?(Array)

        types.concat(schema[key].map { |item| item['type'] }.compact)
      end

      format_type(types) if types.any?
    end

    def format_type(type)
      case type
      when Array
        type.join(' or ')
      when nil
        nil
      else
        type.to_s
      end
    end

    def describe_type(value)
      case value
      when NilClass
        'null'
      when String
        'string'
      when Integer
        'integer'
      when Float
        'number'
      when TrueClass, FalseClass
        'boolean'
      when Array
        'array'
      when Hash
        'object'
      else
        value.class.name
      end
    end

    def source_suffix
      source ? " (#{source})" : ''
    end
  end
end
