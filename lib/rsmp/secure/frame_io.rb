require_relative '../traffic_stats'
require_relative 'cbor'

module RSMP
  module Secure
    # Length-prefixed deterministic-CBOR secure frame reader/writer.
    class FrameIO
      HEADER_SIZE = 4

      attr_reader :stream, :max_frame_size, :traffic_stats

      def initialize(stream, max_frame_size:)
        @stream = stream
        @max_frame_size = Integer(max_frame_size)
        @traffic_stats = TrafficStats.new
      end

      def write(frame)
        payload = Cbor.encode(frame)
        raise FrameError, "Frame too large: #{payload.bytesize} bytes" if payload.bytesize > max_frame_size

        packet = [payload.bytesize].pack('N') + payload
        stream.write(packet)
        @traffic_stats.record_write(packet.bytesize)
        stream.flush unless stream.closed?
      end

      def read
        header = stream.read_exactly(HEADER_SIZE)
        length = header.unpack1('N')
        raise FrameError, "Frame too large: #{length} bytes" if length > max_frame_size

        payload = stream.read_exactly(length)
        @traffic_stats.record_read(HEADER_SIZE + payload.bytesize)
        Cbor.decode(payload)
      rescue EOFError
        raise FrameError, 'Truncated secure frame'
      end
    end
  end
end
