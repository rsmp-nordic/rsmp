module RSMP
  class Error < StandardError
  end

  class InvalidPacket < Error
  end

  class MalformedMessage < Error
  end

  # Raised when schema validation fails.
  class SchemaError < Error
    attr_accessor :schemas
  end

  class InvalidMessage < Error
  end

  class UnknownMessage < Error
  end

  class MissingAcknowledgment < Error
  end

  class MissingWatchdog < Error
  end

  class MessageRejected < Error
  end

  class MissingAttribute < InvalidMessage
  end

  class FatalError < Error
  end

  class HandshakeError < FatalError
  end

  class NotReady < Error
  end

  class TimeoutError < Error
  end

  class DisconnectError < Error
  end

  class ConnectionError < Error
  end

  class UnknownComponent < Error
  end

  class UnknownCommand < Error
  end

  class UnknownStatus < Error
  end

  class ConfigurationError < Error
  end

  class RepeatedAlarmError < Error
  end

  class RepeatedStatusError < Error
  end

  class TimestampError < Error
  end
end
