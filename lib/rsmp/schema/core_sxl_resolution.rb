module RSMP
  # Provides JSON Schema validation for RSMP messages across core and SXL versions.
  module Schema
    def self.clear_core_sxl_schemas(type = nil, version = nil)
      @core_sxl_schemas ||= {}
      return @core_sxl_schemas.clear unless type

      type = type.to_sym
      @core_sxl_schemas.delete_if do |(cached_type, cached_version, _core_version), _schema|
        cached_type == type && (!version || cached_version == version.to_s)
      end
    end

    def self.schema_core_version(schemas)
      schemas[:core] || schemas['core']
    end

    def self.validate_resolved_sxl(message, resolved, schemas, options)
      type, version = resolved
      schema = find_core_sxl_schema! type, version, schema_core_version(schemas), options
      validate_using_schema(message, schema)
    end

    def self.find_core_sxl_schema!(type, version, core_version, options = {})
      raise ArgumentError, 'core version missing' unless core_version

      version = sanitize_version(version.to_s) if options[:lenient]
      core_version = sanitize_version(core_version.to_s) if options[:lenient]
      find_schema! type, version
      find_schema! :core, core_version

      key = [type.to_sym, version.to_s, core_version.to_s]
      @core_sxl_schemas ||= {}
      @core_sxl_schemas[key] ||= build_core_sxl_schema(type, version, core_version)
    end

    def self.build_core_sxl_schema(type, version, core_version)
      schema_path = @schema_paths&.dig(type.to_sym, version.to_s)
      raise UnknownSchemaVersionError, "Unknown schema version #{type} #{version}" unless schema_path

      file_path = File.join(schema_path, 'rsmp.json')
      JSONSchemer.schema(
        Pathname.new(file_path),
        ref_resolver: core_sxl_ref_resolver(core_version)
      )
    end

    def self.core_sxl_ref_resolver(core_version)
      proc do |uri|
        if sxl_definitions_ref?(uri)
          JSON.parse(File.read(core_definitions_path(core_version), encoding: 'UTF-8'))
        else
          JSONSchemer::FILE_URI_REF_RESOLVER.call(uri)
        end
      end
    end

    def self.sxl_definitions_ref?(uri)
      uri.scheme == 'file' && uri.path.end_with?('/defs/definitions.json')
    end

    def self.core_definitions_path(core_version)
      path = File.join(schema_root_path, 'core', core_version.to_s, 'definitions.json')
      return path if File.exist?(path)

      raise UnknownSchemaVersionError, "Missing core definitions for RSMP #{core_version}"
    end
  end
end
