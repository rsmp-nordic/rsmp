require_relative '../traffic_stats'

module RSMP
  # Simple protocol wrapper for reading/writing RSMP framed messages.
  class Protocol
    attr_reader :traffic_stats

    def initialize(stream)
      @stream = stream
      @peeked = nil
      @traffic_stats = TrafficStats.new
    end

    def read_line
      if @peeked
        line = @peeked
        @peeked = nil
        line
      else
        read
      end
    end

    def peek_line
      @peeked ||= read
      @peeked
    end

    def write_lines(data)
      packet = data + RSMP::Proxy::WRAPPING_DELIMITER
      @stream.write(packet)
      @traffic_stats.record_write(packet.bytesize)
      @stream.flush unless @stream.closed?
    end

    protected

    def read
      line = @stream.gets(RSMP::Proxy::WRAPPING_DELIMITER)
      return nil unless line

      @traffic_stats.record_read(line.bytesize)
      line.chomp(RSMP::Proxy::WRAPPING_DELIMITER)
    end
  end
end
