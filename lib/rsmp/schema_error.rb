module RSMP
  module Schema
    # Base error class for rsmp_schema.
    class Error < StandardError
    end

    # Raised when an unknown schema type or version is requested.
    class UnknownSchemaError < Error
    end

    # Raised when the requested schema type does not exist.
    class UnknownSchemaTypeError < UnknownSchemaError
    end

    # Raised when the requested schema version does not exist.
    class UnknownSchemaVersionError < UnknownSchemaError
    end
  end
end
