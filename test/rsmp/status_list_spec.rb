include RSMP

describe StatusList do
  let(:raw) do
    [
      { 'sCI' => 'S0014', 'n' => 'status' },
      { 'sCI' => 'S0014', 'n' => 'source' }
    ]
  end

  let(:hash_symbol_keys) { { S0014: %i[status source] } }
  let(:hash_string_keys) { { 'S0014' => %w[status source] } }

  with '#to_a' do
    it 'returns the raw wire array when initialized from an Array' do
      expect(subject.new(raw).to_a).to be == raw
    end

    it 'converts a Hash with symbol keys to the raw wire array' do
      expect(subject.new(hash_symbol_keys).to_a).to be == raw
    end

    it 'converts a Hash with string keys to the raw wire array' do
      expect(subject.new(hash_string_keys).to_a).to be == raw
    end

    it 'flattens multiple codes' do
      input = { S0001: [:signalGroupStatus], S0002: [:age] }
      result = subject.new(input).to_a
      expect(result).to be == [
        { 'sCI' => 'S0001', 'n' => 'signalGroupStatus' },
        { 'sCI' => 'S0002', 'n' => 'age' }
      ]
    end
  end

  with '#to_h' do
    it 'converts the raw wire array to a compact Hash' do
      result = subject.new(raw).to_h
      expect(result).to be == ({ 'S0014' => %w[status source] })
    end

    it 'roundtrips from Hash through to_a and back via to_h' do
      list = subject.new(hash_string_keys)
      expect(subject.new(list.to_a).to_h).to be == hash_string_keys
    end
  end

  with 'Enumerable' do
    it 'supports map' do
      result = subject.new(raw).map { |item| item['n'] }
      expect(result).to be == %w[status source]
    end

    it 'supports count' do
      expect(subject.new(raw).count).to be == 2
    end

    it 'supports select' do
      result = subject.new(raw).select { |item| item['n'] == 'status' }
      expect(result).to be == [{ 'sCI' => 'S0014', 'n' => 'status' }]
    end
  end

  with 'invalid input' do
    it 'raises ArgumentError for unexpected types' do
      expect { subject.new('bad') }.to raise_exception(ArgumentError)
    end
  end
end
