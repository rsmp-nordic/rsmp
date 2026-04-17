include RSMP

describe CommandList do
  let(:raw) do
    [
      { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'securityCode', 'v' => '1111' },
      { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'status', 'v' => 'NormalControl' }
    ]
  end

  with '#to_a' do
    it 'builds the raw wire array from symbol keys' do
      list = subject.new(:M0001, :setValue, securityCode: '1111', status: 'NormalControl')
      expect(list.to_a).to be == raw
    end

    it 'builds the raw wire array from string keys' do
      list = subject.new('M0001', 'setValue', 'securityCode' => '1111', 'status' => 'NormalControl')
      expect(list.to_a).to be == raw
    end

    it 'converts non-string values to strings' do
      list = subject.new(:M0002, :setPlan, plan: 3, securityCode: 1234)
      expect(list.to_a).to be == [
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'plan', 'v' => '3' },
        { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'securityCode', 'v' => '1234' }
      ]
    end

    it 'omits nil values' do
      list = subject.new(:M0001, :setValue, securityCode: '1111', status: nil)
      expect(list.to_a).to be == [
        { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'securityCode', 'v' => '1111' }
      ]
    end

    it 'returns an empty array for empty values' do
      expect(subject.new(:M0000, :bad, {}).to_a).to be == []
    end
  end

  with '#to_h' do
    it 'returns the compact nested Hash' do
      list = subject.new(:M0001, :setValue, securityCode: '1111', status: 'NormalControl')
      expect(list.to_h).to be == { 'M0001' => { 'setValue' => { 'securityCode' => '1111',
                                                                'status' => 'NormalControl' } } }
    end

    it 'groups multiple codes and commands' do
      list = subject.new(:M0002, :setPlan, plan: '3', securityCode: '1234')
      expect(list.to_h).to be == { 'M0002' => { 'setPlan' => { 'plan' => '3', 'securityCode' => '1234' } } }
    end
  end

  with 'Enumerable' do
    it 'supports map' do
      list = subject.new(:M0001, :setValue, securityCode: '1111', status: 'NormalControl')
      expect(list.map { |item| item['n'] }).to be == %w[securityCode status]
    end

    it 'supports count' do
      list = subject.new(:M0001, :setValue, securityCode: '1111', status: 'NormalControl')
      expect(list.count).to be == 2
    end
  end
end
