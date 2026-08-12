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
        header = stream.read(HEADER_SIZE)
        raise EOFError, 'Secure RSMP peer closed connection' unless header
        raise FrameError, 'Truncated secure frame header' unless header.bytesize == HEADER_SIZE

        length = header.unpack1('N')
        raise FrameError, "Frame too large: #{length} bytes" if length > max_frame_size

        payload = read_payload(length)
        @traffic_stats.record_read(HEADER_SIZE + payload.bytesize)
        Cbor.decode(payload)
      end

      private

      def read_payload(length)
        stream.read_exactly(length)
      rescue EOFError
        raise FrameError, 'Truncated secure frame payload'
      end
    end
  end
end
