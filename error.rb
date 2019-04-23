
module RSMP
	class Error < ArgumentError
	end

	class InvalidPacket < Error
	end

	class InvalidJSON < Error
	end
	
	class InvalidMessage < Error
	end

end
