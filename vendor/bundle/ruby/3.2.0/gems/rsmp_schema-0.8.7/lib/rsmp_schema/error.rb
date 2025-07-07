module RSMP::Schema
  class Error < StandardError
  end

  class UnknownSchemaError < Error
  end

  class UnknownSchemaTypeError < UnknownSchemaError
  end

  class UnknownSchemaVersionError < UnknownSchemaError
  end
end
