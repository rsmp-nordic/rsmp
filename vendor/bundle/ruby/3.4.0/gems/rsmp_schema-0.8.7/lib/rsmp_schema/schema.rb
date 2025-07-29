require 'json_schemer'

module RSMP
end

module RSMP::Schema
  @@schemas = nil

  def self.setup
    @@schemas = {}
    schemas_path = File.expand_path( File.join(__dir__,'..','..','schemas') )
    Dir.glob("#{schemas_path}/*").select {|f| File.directory? f}.each do |type_path|
      type = File.basename(type_path).to_sym
      load_schema_type type, type_path
    end
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
  def self.load_schema_type type, type_path, force:false
    raise RuntimeError.new("Schema type #{type} already loaded") if @@schemas[type] && force!=true
    @@schemas[type] = {}
    Dir.glob("#{type_path}/*").select {|f| File.directory? f}.each do |schema_path|
      version = File.basename(schema_path)
      file_path = File.join(schema_path,'rsmp.json')
      if File.exist? file_path
        @@schemas[type][version] = JSONSchemer.schema(
          Pathname.new(File.join(schema_path,'rsmp.json'))
        )
      end
    end
  end

  # remove a schema type
  def self.remove_schema_type type
    schemas.delete type
  end

  # get schemas types
  def self.schema_types
    schemas.keys
  end

  # get all schemas, oganized by type and version
  def self.schemas
    raise RuntimeError.new("No schemas available, perhaps Schema.setup was never called?") unless @@schemas
    @@schemas
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
  def self.versions type
    schemas = find_schemas!(type).keys
    sort_versions(schemas)
  end

  # get earliest schema version for a particular schema type
  def self.earliest_version type
    schemas = find_schemas!(type).keys
    sort_versions(schemas).first
  end

  # get latest schema version for a particular schema type
  def self.latest_version type
    schemas = find_schemas!(type).keys
    sort_versions(schemas).last
  end

  # validate an rsmp messages using a schema object
  def self.validate_using_schema message, schema
    raise ArgumentError.new("message missing") unless message
    raise ArgumentError.new("schema missing") unless schema
    unless schema.valid? message
      schema.validate(message).map do |item|
        [item['data_pointer'],item['type'],item['details']]
      end
    else
      []
    end
  end

  # sort version strings
  def self.sort_versions versions
    versions.sort_by { |k| Gem::Version.new(k) }
  end

  # find schemas versions for particular schema type
  # return nil if type not found
  def self.find_schemas type
    raise ArgumentError.new("type missing") unless type
    schemas = @@schemas[type.to_sym]
  end

  # find schemas versions for particular schema type
  # raise error if not found
  def self.find_schemas! type
    schemas = find_schemas type
    raise UnknownSchemaTypeError.new("Unknown schema type #{type}") unless schemas
    schemas
  end

  # find schema for a particular schema and version
  # return nil if not found
  def self.find_schema type, version, options={}
    raise ArgumentError.new("version missing") unless version
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
  def self.sanitize_version version
    # match normal semver z.y.z format
    if matched = /^\d+\.\d+\.\d+/.match(version)
      matched.to_s
    # match x.y format, and add patch version zero to get z.y.0
    elsif matched = /^\d+\.\d+/.match(version)
      "#{matched.to_s}.0"
    end
  end

  # find schema for a particular schema and version
  # raise error if not found
  def self.find_schema! type, version, options={}
    schema = find_schema type, version, options
    raise ArgumentError.new("version missing") unless version
    version = sanitize_version version if options[:lenient]
    if version
      schemas = find_schemas! type
      schema = schemas[version]
      return schema if schema
    end
    raise UnknownSchemaVersionError.new("Unknown schema version #{type} #{version}")
  end

  # true if a particular schema type and version found
  def self.has_schema? type, version, options={}
    find_schema(type,version, options) != nil
  end

  # validate using a particular schema and version
  # raises error if schema is not found
  # return nil if validation succeds, otherwise returns an array of errors
  def self.validate message, schemas, options={}
    raise ArgumentError.new("message missing") unless message
    raise ArgumentError.new("schemas missing") unless schemas
    raise ArgumentError.new("schemas must be a Hash") unless schemas.is_a?(Hash)
    raise ArgumentError.new("schemas cannot be empty") unless schemas.any?
    errors = schemas.flat_map do |type, version|
      schema = find_schema! type, version, options
      validate_using_schema(message, schema)
    end
    return nil if errors.empty?
    errors
  end

end
