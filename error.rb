
module RSMP
	class Error < StandardError
	end

	class InvalidPacket < Error
	end

	class MalformedMessage < Error
	end

	class InvalidMessage < Error
	end

	class UnknownMessage < Error
	end

	class MissingAcknowledgment < Error
	end

	class MissingWatchdog < Error
	end

	class MissingAcknowledgment < Error
	end

	class MissingAttribute < InvalidMessage
	end

	class FatalError < Error
	end
end
