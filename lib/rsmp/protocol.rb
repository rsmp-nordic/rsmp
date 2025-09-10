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
      @peeked = read unless @peeked
      @peeked
    end

    def write_lines(data)
      @stream.write(data + RSMP::Proxy::WRAPPING_DELIMITER)
      @stream.flush
    end
  
    protected
    def read
      line = @stream.gets(RSMP::Proxy::WRAPPING_DELIMITER)
      raise EOFError, "Stream closed or no data available" unless line
      line.chomp(RSMP::Proxy::WRAPPING_DELIMITER)
    end
  end
end