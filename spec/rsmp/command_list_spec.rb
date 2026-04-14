include RSMP

RSpec.describe CommandList do
  let(:raw) do
    [
      { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'securityCode', 'v' => '1111' },
      { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'status', 'v' => 'NormalControl' }
    ]
  end

  describe '#to_a' do
    it 'builds the raw wire array from symbol keys' do
      list = described_class.new(:M0001, :setValue, securityCode: '1111', status: 'NormalControl')
      expect(list.to_a).to eq(raw)
    end

    it 'builds the raw wire array from string keys' do
      list = described_class.new('M0001', 'setValue', 'securityCode' => '1111', 'status' => 'NormalControl')
      expect(list.to_a).to eq(raw)
    end

    it 'converts non-string values to strings' do
      list = described_class.new(:M0002, :setPlan, plan: 3, securityCode: 1234)
      expect(list.to_a).to eq([
                                { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'plan', 'v' => '3' },
                                { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'securityCode', 'v' => '1234' }
                              ])
    end

    it 'omits nil values' do
      list = described_class.new(:M0001, :setValue, securityCode: '1111', status: nil)
      expect(list.to_a).to eq([
                                { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'securityCode', 'v' => '1111' }
                              ])
    end

    it 'returns an empty array for empty values' do
      expect(described_class.new(:M0000, :bad, {}).to_a).to eq([])
    end
  end

  describe '#to_h' do
    it 'returns the compact nested Hash' do
      list = described_class.new(:M0001, :setValue, securityCode: '1111', status: 'NormalControl')
      expect(list.to_h).to eq('M0001' => { 'setValue' => { 'securityCode' => '1111', 'status' => 'NormalControl' } })
    end

    it 'groups multiple codes and commands' do
      list = described_class.new(:M0002, :setPlan, plan: '3', securityCode: '1234')
      expect(list.to_h).to eq('M0002' => { 'setPlan' => { 'plan' => '3', 'securityCode' => '1234' } })
    end
  end

  describe 'Enumerable' do
    it 'supports map' do
      list = described_class.new(:M0001, :setValue, securityCode: '1111', status: 'NormalControl')
      expect(list.map { |item| item['n'] }).to eq(%w[securityCode status])
    end

    it 'supports count' do
      list = described_class.new(:M0001, :setValue, securityCode: '1111', status: 'NormalControl')
      expect(list.count).to eq(2)
    end
  end
end
