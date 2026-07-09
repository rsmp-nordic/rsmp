require 'stringio'

describe RSMP::Protocol do
  class ProtocolMemoryStream
    attr_reader :written

    def initialize(input = ''.b)
      @input = StringIO.new(input.b)
      @written = ''.b
    end

    def write(data)
      @written << data.b
      data.bytesize
    end

    def flush; end

    def closed?
      false
    end

    def gets(delimiter)
      @input.gets(delimiter)
    end
  end

  it 'counts legacy framed bytes read and written' do
    stream = ProtocolMemoryStream.new(%({"type":"Watchdog"}\f))
    protocol = subject.new(stream)

    protocol.write_lines('{"type":"Version"}')

    expect(protocol.read_line).to be == '{"type":"Watchdog"}'
    expect(protocol.traffic_stats.written_bytes).to be == stream.written.bytesize
    expect(protocol.traffic_stats.written_frames).to be == 1
    expect(protocol.traffic_stats.read_bytes).to be == %({"type":"Watchdog"}\f).bytesize
    expect(protocol.traffic_stats.read_frames).to be == 1
  end
end
