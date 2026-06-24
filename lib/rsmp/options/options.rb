require 'yaml'
require 'pathname'

module RSMP
  # Base class for configuration options.
  class Options
    SCHEMAS_PATH = File.expand_path('schemas', __dir__)

    attr_reader :data, :log_settings, :source

    def self.load_file(path, validate: true)
      raise RSMP::ConfigurationError, "Config #{path} not found" unless File.exist?(path)
      raise RSMP::ConfigurationError, "Config #{path} is not a file" unless File.file?(path)
      raise RSMP::ConfigurationError, "Config #{path} must be a YAML file (.yml or .yaml)" unless yaml_file?(path)

      raw = YAML.load_file(path)
      raise RSMP::ConfigurationError, "Config #{path} must be a hash" unless raw.is_a?(Hash) || raw.nil?

      raw ||= {}
      log_settings = raw.delete('log') || {}
      new(raw, source: path, log_settings: log_settings, validate: validate)
    rescue Psych::SyntaxError => e
      raise RSMP::ConfigurationError, "Cannot read config file #{path}: #{e}"
    end

    def self.yaml_file?(path)
      %w[.yml .yaml].include?(File.extname(path).downcase)
    end

    def initialize(options = nil, source: nil, log_settings: nil, validate: true, **extra)
      options = extra if options.nil? && extra.any?
      @source = source
      @log_settings = normalize(log_settings || {})
      validate_log_settings! if validate
      config = normalize_config(options || {})
      validate!(config) if validate
      @data = normalize(apply_defaults(config))
    end

    def defaults = {}

    def schema_file = nil

    def schema_path = schema_file && File.join(SCHEMAS_PATH, schema_file)

    def log_schema_path = File.join(SCHEMAS_PATH, 'log.json')

    def validate_log_settings!
      return unless File.exist?(log_schema_path)

      schemer = JSONSchemer.schema(Pathname.new(log_schema_path))
      errors = schemer.validate(@log_settings).to_a
      return if errors.empty?

      message = errors.map { |error| format_error(error) }.join("\n")
      raise RSMP::ConfigurationError, "Invalid log configuration#{source_suffix}:\n#{message}"
    end

    def validate!(data = @data)
      return unless schema_path && File.exist?(schema_path)

      schemer = JSONSchemer.schema(Pathname.new(schema_path))
      errors = schemer.validate(data).to_a
      return if errors.empty?

      message = errors.map { |error| format_error(error) }.join("\n")
      raise RSMP::ConfigurationError, "Invalid configuration#{source_suffix}:\n#{message}"
    end

    def dig(*path, default: nil, assume: nil)
      value = @data.dig(*path)
      return value unless value.nil?
      return default unless default.nil?
      return assume unless assume.nil?

      raise RSMP::ConfigurationError, "Config #{path.inspect} is missing"
    end

    def [](key)
      @data[key]
    end

    def to_h
      @data
    end

    private

    def apply_defaults(options)
      defaults.deep_merge(options)
    end

    def normalize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), memo|
          normalized_key = key.to_s
          memo[normalized_key] = normalized_key == 'sxls' ? normalize_sxls(val) : normalize(val)
        end
      when Array
        value.map { |item| normalize(item) }
      else
        value
      end
    end

    def normalize_sxls(value)
      case value
      when Hash
        value.map do |name, details|
          normalize_sxl_item(name.to_s, details)
        end
      when Array
        value.map { |item| normalize(item) }
      else
        value
      end
    end

    def normalize_config(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), memo|
          normalized_key = key.to_s
          memo[normalized_key] = normalized_key == 'sxls' ? normalize_config_sxls(val) : normalize_config(val)
        end
      when Array
        value.map { |item| normalize_config(item) }
      else
        value
      end
    end

    def normalize_config_sxls(value)
      raise RSMP::ConfigurationError, 'sxls must be a hash of SXL names to versions' unless value.is_a?(Hash)

      value.each_with_object({}) do |(name, details), memo|
        raise RSMP::ConfigurationError, "sxls/#{name} must be a version string" if details.is_a?(Hash)

        memo[name.to_s] = details.to_s
      end
    end

    def normalize_sxl_item(name, details)
      case details
      when Hash
        raise RSMP::ConfigurationError, "sxls/#{name} must be a version string"
      when nil
        { 'name' => name }
      else
        { 'name' => name, 'version' => details.to_s }
      end
    end

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
