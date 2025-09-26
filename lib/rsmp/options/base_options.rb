require 'json'
require_relative '../deep_merge'

module RSMP
  module Options
    # Base class for all RSMP configuration options
    # Provides common functionality for configuration validation, defaults, and merging
    class BaseOptions
      attr_reader :config, :validation_errors

      def initialize(config = {})
        @config = {}
        @validation_errors = []
        
        # Start with defaults, then merge in provided config
        @config = defaults.deep_merge(normalize_config(config))
        
        # Validate the final configuration
        validate!
      end

      # Get a configuration value by key path using Ruby's dig method
      def get(*keys)
        @config.dig(*keys)
      end

      # Set a configuration value by key path
      def set(key_path, value)
        keys = key_path.to_s.split('.')
        target = @config
        keys[0..-2].each do |key|
          target[key] ||= {}
          target = target[key]
        end
        target[keys.last] = value
        validate!
        value
      end

      # Get the complete configuration as a hash
      def to_h
        @config.dup
      end

      # Merge additional configuration
      def merge!(other_config)
        @config = @config.deep_merge(normalize_config(other_config))
        validate!
        self
      end

      # Check if configuration is valid
      def valid?
        @validation_errors.empty?
      end

      protected

      # Override in subclasses to provide default configuration
      def defaults
        {}
      end

      # Override in subclasses to provide JSON schema for validation
      def schema
        nil
      end

      # Override in subclasses for custom validation
      def custom_validations
        # Returns array of error messages, empty if valid
        []
      end

      private

      def normalize_config(config)
        case config
        when Hash
          config
        when String
          # Assume it's a file path
          if File.exist?(config)
            require 'yaml'
            YAML.load_file(config)
          else
            raise ConfigurationError, "Configuration file not found: #{config}"
          end
        else
          raise ConfigurationError, "Invalid configuration type: #{config.class}"
        end
      end

      def validate!
        @validation_errors = []
        
        # JSON Schema validation if schema is provided
        if schema
          validate_with_schema
        end
        
        # Custom validations
        @validation_errors.concat(custom_validations)
        
        # Raise error if invalid
        unless valid?
          raise ConfigurationError, "Configuration validation failed: #{@validation_errors.join(', ')}"
        end
      end

      def validate_with_schema
        begin
          require 'json_schemer'
          schemer = JSONSchemer.schema(schema)
          result = schemer.validate(@config)
          result.each do |error|
            @validation_errors << format_schema_error(error)
          end
        rescue LoadError
          # JSON schema validation is optional
        end
      end

      def format_schema_error(error)
        path = error['data_pointer'].empty? ? 'root' : error['data_pointer']
        "#{path}: #{error['details'] || error['error']}"
      end
    end
  end
end