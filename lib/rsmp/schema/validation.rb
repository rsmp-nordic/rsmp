module RSMP
  # Provides JSON Schema validation for RSMP messages across core and SXL versions.
  module Schema
    def self.core_message_type?(message)
      type = message['type']
      %w[
        MessageAck
        MessageNotAck
        Version
        ComponentList
        AggregatedStatus
        AggregatedStatusRequest
        Watchdog
      ].include?(type)
    end

    def self.validate_core(message, schemas, options)
      core_version = schemas[:core] || schemas['core']
      raise ArgumentError, 'schemas must include core' unless core_version

      schema = find_schema! :core, core_version, options
      validate_using_schema(message, schema)
    end

    def self.validate_sxls(message, schemas, options)
      sxl_schemas = schemas.reject { |type, _version| type.to_sym == :core }
      return [] if sxl_schemas.empty? || core_message_type?(message)

      resolved = resolve_sxl(message, schemas: schemas, **options)
      return validate_resolved_sxl(message, resolved, schemas, options) if resolved

      all_errors = []
      sxl_schemas.each do |type, version|
        schema = find_core_sxl_schema! type, version, schema_core_version(schemas), options
        errors = validate_using_schema(message, schema)
        return [] if errors.empty?

        all_errors.concat errors
      end
      all_errors
    end

    # Core must pass. SXL-defined messages pass if at least one SXL schema passes.
    def self.validate(message, schemas, options = {})
      raise ArgumentError, 'message missing' unless message
      raise ArgumentError, 'schemas missing' unless schemas
      raise ArgumentError, 'schemas must be a Hash' unless schemas.is_a?(Hash)
      raise ArgumentError, 'schemas cannot be empty' unless schemas.any?

      errors = validate_core(message, schemas, options)
      errors.concat validate_sxls(message, schemas, options) if errors.empty?
      return nil if errors.empty?

      errors
    end
  end
end
