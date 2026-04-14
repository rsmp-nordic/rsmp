include RSMP

RSpec.describe StatusList do
  let(:raw) do
    [
      { 'sCI' => 'S0014', 'n' => 'status' },
      { 'sCI' => 'S0014', 'n' => 'source' }
    ]
  end

  let(:hash_symbol_keys) { { S0014: %i[status source] } }
  let(:hash_string_keys) { { 'S0014' => %w[status source] } }

  describe '#to_a' do
    it 'returns the raw wire array when initialized from an Array' do
      expect(described_class.new(raw).to_a).to eq(raw)
    end

    it 'converts a Hash with symbol keys to the raw wire array' do
      expect(described_class.new(hash_symbol_keys).to_a).to eq(raw)
    end

    it 'converts a Hash with string keys to the raw wire array' do
      expect(described_class.new(hash_string_keys).to_a).to eq(raw)
    end

    it 'flattens multiple codes' do
      input = { S0001: [:signalGroupStatus], S0002: [:age] }
      result = described_class.new(input).to_a
      expect(result).to eq([
                             { 'sCI' => 'S0001', 'n' => 'signalGroupStatus' },
                             { 'sCI' => 'S0002', 'n' => 'age' }
                           ])
    end
  end

  describe '#to_h' do
    it 'converts the raw wire array to a compact Hash' do
      result = described_class.new(raw).to_h
      expect(result).to eq('S0014' => %w[status source])
    end

    it 'roundtrips from Hash through to_a and back via to_h' do
      list = described_class.new(hash_string_keys)
      expect(described_class.new(list.to_a).to_h).to eq(hash_string_keys)
    end
  end

  describe 'Enumerable' do
    it 'supports map' do
      result = described_class.new(raw).map { |item| item['n'] }
      expect(result).to eq(%w[status source])
    end

    it 'supports count' do
      expect(described_class.new(raw).count).to eq(2)
    end

    it 'supports select' do
      result = described_class.new(raw).select { |item| item['n'] == 'status' }
      expect(result).to eq([{ 'sCI' => 'S0014', 'n' => 'status' }])
    end
  end

  describe 'invalid input' do
    it 'raises ArgumentError for unexpected types' do
      expect { described_class.new('bad') }.to raise_error(ArgumentError)
    end
  end
end
