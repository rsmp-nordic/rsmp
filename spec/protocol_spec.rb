RSpec.describe RSMP::Protocol do
  describe '#initialize' do
    it 'accepts one argument (stream)' do
      stream = double('stream')
      expect { RSMP::Protocol.new(stream) }.not_to raise_error
    end

    it 'rejects two arguments' do
      stream = double('stream')
      delimiter = "\f"
      expect { RSMP::Protocol.new(stream, delimiter) }.to raise_error(ArgumentError)
    end
  end

  describe '#write_lines' do
    let(:stream) { double('stream', write: nil, flush: nil) }
    let(:protocol) { RSMP::Protocol.new(stream) }

    it 'writes data with delimiter' do
      data = '{"test": "data"}'
      expect(stream).to receive(:write).with(data + RSMP::Proxy::WRAPPING_DELIMITER)
      expect(stream).to receive(:flush)
      protocol.write_lines(data)
    end
  end

  describe '#read_line and #peek_line' do
    let(:stream) { double('stream') }
    let(:protocol) { RSMP::Protocol.new(stream) }

    it 'reads line from stream' do
      allow(stream).to receive(:gets).with(RSMP::Proxy::WRAPPING_DELIMITER).and_return("test data\f")

      result = protocol.read_line
      expect(result).to eq('test data')
    end

    it 'handles peek functionality' do
      allow(stream).to receive(:gets).with(RSMP::Proxy::WRAPPING_DELIMITER).and_return("test data\f")

      # First peek should read and cache the line
      result1 = protocol.peek_line
      expect(result1).to eq('test data')

      # Second peek should return cached value
      result2 = protocol.peek_line
      expect(result2).to eq('test data')

      # Read should return cached value and clear cache
      result3 = protocol.read_line
      expect(result3).to eq('test data')
    end
  end
end
