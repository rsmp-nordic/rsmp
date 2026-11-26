require 'yaml'
require 'pathname'
require_relative 'sxl_options'
require_relative 'error_formatting'

module RSMP
  # Base class for configuration options.
  class Options
    include SxlOptions
    include OptionsErrorFormatting

    SCHEMAS_PATH = File.expand_path('schemas', __dir__)
    INTERNAL_KEYS = ['__config_dir'].freeze

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
      raw_options = options || {}
      config = normalize_config(public_settings(raw_options))
      validate!(config) if validate
      config = apply_defaults(config)
      validate_effective!(config) if validate
      @data = normalize(config).merge(internal_settings(raw_options))
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

    def validate!(data = @data, path: schema_path)
      return unless path && File.exist?(path)

      schemer = JSONSchemer.schema(Pathname.new(path))
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

    def validate_effective!(_config); end

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

    def internal_settings(options)
      settings = options.is_a?(Hash) ? options.transform_keys(&:to_s).slice(*INTERNAL_KEYS) : {}
      settings['__config_dir'] ||= File.dirname(File.expand_path(source)) if source
      settings
    end

    def public_settings(options)
      return options unless options.is_a?(Hash)

      options.reject { |key, _value| INTERNAL_KEYS.include?(key.to_s) }
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
  end
end
