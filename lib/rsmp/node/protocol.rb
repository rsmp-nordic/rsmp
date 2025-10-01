module RSMP
  class Protocol
    def initialize(stream)
      @stream = stream
      @peeked = nil
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
      @stream.write(data + RSMP::Proxy::WRAPPING_DELIMITER)
      @stream.flush if flushable?
    end

    protected

    def flushable?
      return true unless @stream.respond_to?(:closed?)

      !@stream.closed?
    end

    def read
      line = @stream.gets(RSMP::Proxy::WRAPPING_DELIMITER)
      return nil unless line

      line.chomp(RSMP::Proxy::WRAPPING_DELIMITER)
    end
  end
end
