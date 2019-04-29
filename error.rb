
module RSMP
	class Error < ArgumentError
	end

	class InvalidPacket < Error
	end

	class InvalidJSON < Error
	end

	class InvalidMessage < Error
	end

	class UnknownMessageType < Error
	end

	class MissingAcknowledgment < Error
	end

	class BadConnectionSequence < Error
	end

	class MissingWatchdog < Error
	end

	class MissingAcknowledgment < Error
	end
end
