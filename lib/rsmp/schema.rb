require 'json_schemer'
require 'json'

# RSMP (Road Side Message Protocol) schema validation library.
module RSMP
  # Provides JSON Schema validation for RSMP messages across core and SXL versions.
  module Schema
    @schemas = nil

    def self.setup
      @schemas = {}
      @schema_paths = {}
      @sxl_indexes = {}
      @core_sxl_schemas = {}
      schemas_path = schema_root_path
      Dir.glob("#{schemas_path}/*").select { |f| File.directory? f }.each do |type_path|
        type = File.basename(type_path).to_sym
        load_schema_type type, type_path
      end
    end

    def self.schema_root_path
      File.expand_path(File.join(__dir__, '..', '..', 'schemas'))
    end

    # load an schema from a folder. schemas are organized by version, and contain
    # json schema files, with the entry point being rsmp.jspon, eg:
    # tlc
    #   1.0.7
    #     rsmp.json
    #     other jon schema files...
    #   1.0.8
    #   ...
    #
    #  an error is raised if the schema type already exists, and force is not set to true
    def self.load_schema_type(type, type_path, force: false)
      type = type.to_sym
      ensure_schema_type_available(type, force)

      @schemas[type] = {}
      @schema_paths ||= {}
      @schema_paths[type] = {}
      clear_sxl_index(type)
      clear_core_sxl_schemas(type)
      schema_version_paths(type_path).each { |schema_path| load_schema_version(type, schema_path) }
    end

    def self.ensure_schema_type_available(type, force)
      raise "Schema type #{type} already loaded" if @schemas[type] && force != true
    end

    def self.schema_version_paths(type_path)
      Dir.glob("#{type_path}/*").select { |path| File.directory? path }
    end

    def self.load_schema_version(type, schema_path)
      version = File.basename(schema_path)
      file_path = File.join(schema_path, 'rsmp.json')
      return unless File.exist? file_path

      @schemas[type][version] = JSONSchemer.schema(Pathname.new(file_path))
      @schema_paths[type][version] = schema_path
      clear_sxl_index(type, version)
      clear_core_sxl_schemas(type, version)
    end

    # remove a schema type
    def self.remove_schema_type(type)
      type = type.to_sym
      schemas.delete type
      @schema_paths&.delete type
      clear_sxl_index(type)
      clear_core_sxl_schemas(type)
    end

    # get schemas types
    def self.schema_types
      schemas.keys
    end

    # get all schemas, oganized by type and version
    def self.schemas
      raise 'No schemas available, perhaps Schema.setup was never called?' unless @schemas

      @schemas
    end

    # get array of core schema versions
    def self.core_versions
      versions :core
    end

    # get earliest core schema version
    def self.earliest_core_version
      earliest_version :core
    end

    # get latesty core schema version
    def self.latest_core_version
      latest_version :core
    end

    # get array of  schema versions for a particular schema type
    def self.versions(type)
      schemas = find_schemas!(type).keys
      sort_versions(schemas)
    end

    # get earliest schema version for a particular schema type
    def self.earliest_version(type)
      schemas = find_schemas!(type).keys
      sort_versions(schemas).first
    end

    # get latest schema version for a particular schema type
    def self.latest_version(type)
      schemas = find_schemas!(type).keys
      sort_versions(schemas).last
    end

    # validate an rsmp messages using a schema object
    def self.validate_using_schema(message, schema)
      raise ArgumentError, 'message missing' unless message
      raise ArgumentError, 'schema missing' unless schema

      if schema.valid? message
        []
      else
        schema.validate(message).map do |item|
          [item['data_pointer'], item['type'], item['details']]
        end
      end
    end

    # sort version strings
    def self.sort_versions(versions)
      versions.sort_by { |k| Gem::Version.new(k) }
    end

    # find schemas versions for particular schema type
    # return nil if type not found
    def self.find_schemas(type)
      raise ArgumentError, 'type missing' unless type

      @schemas[type.to_sym]
    end

    # find schemas versions for particular schema type
    # raise error if not found
    def self.find_schemas!(type)
      schemas = find_schemas type
      raise UnknownSchemaTypeError, "Unknown schema type #{type}" unless schemas

      schemas
    end

    # find schema for a particular schema and version
    # return nil if not found
    def self.find_schema(type, version, options = {})
      raise ArgumentError, 'version missing' unless version

      version = sanitize_version version if options[:lenient]
      if version
        schemas = find_schemas type
        return schemas[version] if schemas
      end
      nil
    end

    # get major.minor.patch part of a version string, where patch is optional
    # ignore trailing characters, e.g.
    #   3.1.3.32A => 3.1.3
    #   3.1A3r3 >= 3.1
    # return nil if string doesn't match
    def self.sanitize_version(version)
      # match normal semver z.y.z format
      if (matched = /^\d+\.\d+\.\d+/.match(version))
        matched.to_s
      # match x.y format, and add patch version zero to get z.y.0
      elsif (matched = /^\d+\.\d+/.match(version))
        "#{matched}.0"
      end
    end

    # find schema for a particular schema and version
    # raise error if not found
    def self.find_schema!(type, version, options = {})
      schema = find_schema type, version, options
      raise ArgumentError, 'version missing' unless version

      version = sanitize_version version if options[:lenient]
      if version
        schemas = find_schemas! type
        schema = schemas[version]
        return schema if schema
      end
      raise UnknownSchemaVersionError, "Unknown schema version #{type} #{version}"
    end

    # true if a particular schema type and version found
    def self.schema?(type, version, options = {})
      find_schema(type, version, options) != nil
    end

    def self.sxl_metadata(type, version, options = {})
      version = sanitize_version version if options[:lenient]
      find_schema! type, version

      sxl_index(type, version).fetch('meta', {})
    end

    def self.sxl_prefix(type, version, options = {})
      sxl_metadata(type, version, options)['prefix']
    end

    # return a catalogue of statuses for a particular schema type and version
    # returns a hash of { status_code_id_sym => [arg_name_sym, ...] }
    # raises an error if the schema type/version is not found, or has no status catalogue
    def self.status_catalogue(type, version)
      sxl_catalogue(type, version, :statuses).transform_keys(&:to_sym).transform_values do |status|
        (argument_names(status['required']) + argument_names(status['optional'])).sort.map(&:to_sym)
      end
    end

    def self.argument_names(arguments)
      case arguments
      when Hash
        arguments.keys
      when Array
        arguments
      else
        []
      end
    end

    def self.sxl_catalogue_item(type, version, kind, code, options = {})
      version = sanitize_version(version.to_s) if options[:lenient]
      catalogue = sxl_catalogue(type, version, kind)
      prefix = sxl_prefix(type, version, options)
      code = code.to_s
      unprefixed = prefix && code.start_with?(prefix) ? code[prefix.length..] : code
      catalogue[code] || catalogue[code.to_sym] ||
        catalogue[unprefixed] || catalogue[unprefixed.to_sym]
    end

    def self.sxl_argument_descriptor(type, version, kind, code, name)
      item = sxl_catalogue_item(type, version, kind, code)
      return unless item

      argument_descriptor(item['required'], name) || argument_descriptor(item['optional'], name)
    end

    def self.argument_descriptor(arguments, name)
      return unless arguments

      case arguments
      when Hash
        arguments[name] || arguments[name.to_sym]
      end
    end

    def self.sxl_catalogue(type, version, kind)
      find_schema! type, version
      catalogue = sxl_index(type, version)[kind.to_s]
      raise "No #{kind} catalogue for #{type} #{version}" unless catalogue

      catalogue
    end

    def self.clear_sxl_index(type = nil, version = nil)
      @sxl_indexes ||= {}
      return @sxl_indexes.clear unless type

      type = type.to_sym
      if version
        @sxl_indexes.delete([type, version.to_s])
      else
        @sxl_indexes.delete_if { |key, _value| key.first == type }
      end
    end

    def self.sxl_index(type, version)
      key = [type.to_sym, version.to_s]
      @sxl_indexes ||= {}
      @sxl_indexes[key] ||= load_sxl_index(type, version)
    end

    def self.load_sxl_index(type, version)
      schema_path = @schema_paths&.dig(type.to_sym, version.to_s)
      raise UnknownSchemaVersionError, "Unknown schema version #{type} #{version}" unless schema_path

      index_path = File.join(schema_path, 'sxl_index.json')
      raise Error, "Missing SXL index #{index_path}" unless File.exist?(index_path)

      JSON.parse(File.read(index_path, encoding: 'UTF-8'))
    end
  end
end

require_relative 'schema/core_sxl_resolution'
require_relative 'schema/message_resolution'
require_relative 'schema/validation'
