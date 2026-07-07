require_relative 'cbor'

module RSMP
  module Secure
    # Length-prefixed deterministic-CBOR secure frame reader/writer.
    class FrameIO
      HEADER_SIZE = 4

      attr_reader :stream, :max_frame_size

      def initialize(stream, max_frame_size:)
        @stream = stream
        @max_frame_size = Integer(max_frame_size)
      end

      def write(frame)
        payload = Cbor.encode(frame)
        raise FrameError, "Frame too large: #{payload.bytesize} bytes" if payload.bytesize > max_frame_size

        stream.write([payload.bytesize].pack('N') + payload)
        stream.flush unless stream.closed?
      end

      def read
        header = stream.read_exactly(HEADER_SIZE)
        length = header.unpack1('N')
        raise FrameError, "Frame too large: #{length} bytes" if length > max_frame_size

        Cbor.decode(stream.read_exactly(length))
      rescue EOFError
        raise FrameError, 'Truncated secure frame'
      end
    end
  end
end
