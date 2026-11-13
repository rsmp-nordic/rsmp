require 'rsmp'

describe RSMP::SubscriptionMatcher do
  it 'matches the requested status code and optional field name' do
    matcher = subject.new('sCI' => 'S0014', 'n' => 'status')
    expect(matcher.match('sCI' => 'S0014', 'n' => 'status')).to be == true
    expect(matcher.match('sCI' => 'S0001', 'n' => 'status')).to be_nil
    expect(matcher.match('sCI' => 'S0014', 'n' => 'source')).to be_nil
    expect(matcher.match('n' => 'status')).to be_nil
  end

  it 'matches any field when only the code is specified' do
    matcher = subject.new('sCI' => 'S0014')
    %w[status source].each do |name|
      expect(matcher.match('sCI' => 'S0014', 'n' => name)).to be == true
    end
  end

  it 'checks explicitly requested update rates' do
    matcher = subject.new('sCI' => 'S0014', 'uRt' => '1')
    expect(matcher.match('sCI' => 'S0014', 'uRt' => '1')).to be == true
    expect(matcher.match('sCI' => 'S0014', 'uRt' => '2')).to be == false
    expect(matcher.match('sCI' => 'S0014')).to be == false
  end

  it 'distinguishes false send-on-change from true and an omitted field' do
    matcher = subject.new('sCI' => 'S0014', 'sOc' => false)
    expect(matcher.match('sCI' => 'S0014', 'sOc' => false)).to be == true
    expect(matcher.match('sCI' => 'S0014', 'sOc' => true)).to be == false
    expect(matcher.match('sCI' => 'S0014')).to be == false
  end

  it 'requires all specified settings to match' do
    matcher = subject.new('sCI' => 'S0014', 'n' => 'status', 'uRt' => '1', 'sOc' => true)
    item = { 'sCI' => 'S0014', 'n' => 'status', 'uRt' => '1', 'sOc' => true }
    expect(matcher.match(item)).to be == true
    expect(matcher.match(item.merge('uRt' => '0'))).to be == false
    expect(matcher.match(item.merge('sOc' => false))).to be == false
  end

  it 'ignores unspecified settings and also matches unsubscribe items' do
    matcher = subject.new('sCI' => 'S0014', 'n' => 'status')
    item = { 'sCI' => 'S0014', 'n' => 'status' }
    expect(matcher.match(item)).to be == true
    expect(matcher.match(item.merge('uRt' => '1', 'sOc' => false))).to be == true
    expect(matcher.match(item.merge('uRt' => '0', 'sOc' => true))).to be == true
  end
end

describe RSMP::StatusMatcher do
  it 'preserves code, name and operation matching with the shared implementation' do
    matcher = subject.new('sCI' => 'S0014', 'n' => 'status', 'cO' => 'test')
    item = { 'sCI' => 'S0014', 'n' => 'status', 'cO' => 'test' }
    expect(matcher.match(item)).to be == true
    %w[sCI n cO].each do |key|
      expect(matcher.match(item.merge(key => 'other'))).to be_nil
    end
  end

  it 'still checks status values and quality independently of subscription settings' do
    matcher = subject.new('sCI' => 'S0014', 's' => false, 'q' => 'recent')
    item = { 'sCI' => 'S0014', 's' => false, 'q' => 'recent' }
    expect(matcher.match(item)).to be == true
    expect(matcher.match(item.merge('s' => true))).to be == false
    expect(matcher.match(item.merge('q' => 'undefined'))).to be == false
    expect(matcher.match(item.merge('uRt' => '1', 'sOc' => false))).to be == true
  end
end
