module RSMP
  # Counts application transport bytes and frames/messages for one connection.
  class TrafficStats
    attr_reader :read_bytes, :written_bytes, :read_frames, :written_frames

    def initialize
      @read_bytes = 0
      @written_bytes = 0
      @read_frames = 0
      @written_frames = 0
    end

    def record_read(bytes)
      @read_bytes += bytes
      @read_frames += 1
    end

    def record_write(bytes)
      @written_bytes += bytes
      @written_frames += 1
    end

    def empty?
      read_frames.zero? && written_frames.zero?
    end

    def summary
      "Traffic counters: read #{read_bytes} bytes in #{read_frames} frames, " \
        "wrote #{written_bytes} bytes in #{written_frames} frames"
    end
  end
end
