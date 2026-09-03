module RSMP
  class Error < StandardError
  end

  class InvalidPacket < Error
  end

  class MalformedMessage < Error
  end

  # Semantic failures which may be raised while processing a schema-valid peer
  # message. The receive boundary converts only this explicit family to a peer
  # Failure; unrelated exceptions retain their original stack trace.
  class PeerMessageError < Error
  end

  # Raised when schema validation fails.
  class SchemaError < Error
    attr_accessor :schemas
  end

  class InvalidMessage < PeerMessageError
  end

  class UnknownMessage < Error
  end

  class MessageRejected < PeerMessageError
  end

  class MissingAttribute < InvalidMessage
  end

  class FatalError < Error
  end

  class HandshakeError < FatalError
  end

  class ConnectionError < Error
  end

  class UnknownComponent < PeerMessageError
  end

  class UnknownCommand < PeerMessageError
  end

  class UnknownStatus < PeerMessageError
  end

  class ConfigurationError < Error
  end

  class RepeatedAlarmError < PeerMessageError
  end

  class RepeatedStatusError < PeerMessageError
  end

  class TimestampError < PeerMessageError
  end
end
