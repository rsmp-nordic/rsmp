describe RSMP::ItemFilter do
  def message(type, attributes = {}, direction: :in, **extra)
    RSMP.const_get(type).new(attributes.merge(extra)).tap { |item| item.direction = direction }
  end

  [
    [RSMP::StatusFilter, RSMP::StatusMatcher, { 'StatusUpdate' => 'sS', 'StatusResponse' => 'sS' },
     { 'sCI' => 'S0014', 'n' => 'status', 's' => 2 }, { 'sCI' => 'S0007', 'n' => 'status', 's' => [true] }],
    [RSMP::SubscriptionFilter, RSMP::SubscriptionMatcher, { 'StatusSubscribe' => 'sS', 'StatusUnsubscribe' => 'sS' },
     { 'sCI' => 'S0014', 'n' => 'status' }, { 'sCI' => 'S0007', 'n' => 'status' }],
    [RSMP::CommandFilter, RSMP::CommandMatcher, { 'CommandRequest' => 'arg', 'CommandResponse' => 'rvs' },
     { 'cCI' => 'M0002', 'n' => 'status', 'v' => true }, { 'cCI' => 'M0002', 'n' => 'timeplan', 'v' => 2 }],
    [RSMP::AlarmFilter, RSMP::AlarmMatcher, { 'Alarm' => 'rvs' },
     { 'n' => 'color', 'v' => 'green' }, { 'n' => 'reason', 'v' => 'test' }]
  ].each do |filter_class, matcher_class, types, first, second|
    with filter_class.name do
      let(:matchers) { [matcher_class.new(first), matcher_class.new(second)] }

      it 'defaults to its message family without requiring items' do
        filter = filter_class.new
        types.each_key { |type| expect(filter.accept?(message(type))).to be == true }
        expect(filter.accept?(message('Watchdog'))).to be == false
      end

      it 'narrows type, direction and component independently of content matching' do
        type, key = types.first
        filter = filter_class.new(type: type, outgoing: false, component: 'TC', all: matchers)
        attributes = { 'cId' => 'TC', key => [first, second] }
        expect(filter.accept?(message(type, attributes))).to be == true
        expect(filter.accept?(message(type, attributes, direction: :out))).to be == false
        expect(filter.accept?(message(type, attributes.merge('cId' => 'OTHER')))).to be == false
        types.keys.drop(1).each { |other| expect(filter.accept?(message(other, attributes))).to be == false }
      end

      it 'requires every matcher within one message and allows extra items' do
        filter = filter_class.new(all: matchers)
        types.each do |type, key|
          expect(filter.accept?(message(type, key => [first]))).to be == false
          expect(filter.accept?(message(type, key => [second]))).to be == false
          expect(filter.accept?(message(type, key => [first, second, { 'n' => 'unrelated' }]))).to be == true
          expect(filter.accept?(message(type))).to be == false
        end
      end

      it 'accepts any successful matcher and permits one item to satisfy multiple matchers' do
        filter = filter_class.new(any: matchers)
        type, key = types.first
        expect(filter.accept?(message(type, key => [second]))).to be == true
        expect(filter.accept?(message(type, key => [{ 'n' => 'unrelated' }]))).to be == false
        repeated = filter_class.new(all: [matcher_class.new(first), matcher_class.new(first)])
        expect(repeated.accept?(message(type, key => [first]))).to be == true
      end

      it 'does not keep or clear collector matcher state during filtering' do
        type, key = types.first
        earlier = message(type, key => [first])
        matchers.first.keep(earlier, first)
        filter = filter_class.new(all: matchers)
        filter.accept?(message(type, key => [first, second]))
        filter.accept?(message(type, key => [{ 'n' => 'unrelated' }]))
        expect(matchers.first.got).to be == first
        expect(matchers.first.message).to be == earlier
        expect(matchers.last.done?).to be == false
      end

      it 'admits NotAck without items, while respecting direction and component' do
        filter = filter_class.new(outgoing: false, component: 'TC', all: matchers)
        expect(filter.accept?(message('MessageNotAck'))).to be == true
        expect(filter.accept?(message('MessageNotAck', {}, direction: :out))).to be == false
        expect(filter.accept?(message('MessageNotAck', 'cId' => 'OTHER'))).to be == false
        expect(filter.items(message('MessageNotAck'))).to be == []
      end

      it 'rejects invalid types, matcher kinds, lists and conflicting match modes' do
        wrong_matcher = matcher_class == RSMP::StatusMatcher ? RSMP::CommandMatcher.new({}) : RSMP::StatusMatcher.new({})
        expect { filter_class.new(type: 'Watchdog') }.to raise_exception(ArgumentError)
        expect { filter_class.new(all: [wrong_matcher]) }.to raise_exception(ArgumentError)
        expect { filter_class.new(any: [wrong_matcher]) }.to raise_exception(ArgumentError)
        expect { filter_class.new(all: []) }.to raise_exception(ArgumentError)
        expect { filter_class.new(any: []) }.to raise_exception(ArgumentError)
        expect { filter_class.new(any: matchers.first) }.to raise_exception(ArgumentError)
        expect { filter_class.new(all: matchers, any: matchers) }.to raise_exception(ArgumentError)
      end
    end
  end

  it 'checks status quality, false values and regex values' do
    filter = RSMP::StatusFilter.new(all: [RSMP::StatusMatcher.new('sCI' => 'S0005', 'q' => 'recent', 's' => false)])
    item = { 'sCI' => 'S0005', 'q' => 'recent', 's' => false }
    expect(filter.accept?(message('StatusUpdate', 'sS' => [item]))).to be == true
    expect(filter.accept?(message('StatusUpdate', 'sS' => [item.merge('q' => 'undefined')]))).to be == false
    regex = RSMP::StatusFilter.new(any: [RSMP::StatusMatcher.new('sCI' => 'S0001', 's' => /^3+$/)])
    expect(regex.accept?(message('StatusUpdate', 'sS' => [{ 'sCI' => 'S0001', 's' => '333' }]))).to be == true
  end

  it 'matches explicit subscription settings without treating false as absent' do
    filter = RSMP::SubscriptionFilter.new(all: [RSMP::SubscriptionMatcher.new('sCI' => 'S0014', 'sOc' => false, 'uRt' => '1')])
    item = { 'sCI' => 'S0014', 'sOc' => false, 'uRt' => '1' }
    expect(filter.accept?(message('StatusSubscribe', 'sS' => [item]))).to be == true
    expect(filter.accept?(message('StatusSubscribe', 'sS' => [item.except('sOc')]))).to be == false
    expect(filter.accept?(message('StatusSubscribe', 'sS' => [item.merge('uRt' => '2')]))).to be == false
  end

  it 'combines alarm attribute comparisons with return-value matchers' do
    filter = RSMP::AlarmFilter.new(attributes: { 'aCId' => 'A0301', 'aS' => 'Active', 'aSp' => /^Issue$/ },
                                   any: [RSMP::AlarmMatcher.new('n' => 'color', 'v' => /^green/)])
    attributes = { 'aCId' => 'A0301', 'aS' => 'active', 'aSp' => 'Issue', 'rvs' => [{ 'n' => 'color', 'v' => 'greenish' }] }
    expect(filter.accept?(message('Alarm', attributes))).to be == true
    expect(filter.accept?(message('Alarm', attributes.merge('aCId' => 'a0301')))).to be == false
    expect(filter.accept?(message('Alarm', attributes.merge('aSp' => 'issue')))).to be == false
    expect(filter.accept?(message('Alarm', attributes.merge('rvs' => [])))).to be == false
    expect(filter.accept?(message('MessageNotAck'))).to be == true
  end

  it 'matches an explicit false alarm return value' do
    filter = RSMP::AlarmFilter.new(any: [RSMP::AlarmMatcher.new('n' => 'flag', 'v' => false)])
    [true, false].each do |value|
      alarm = message('Alarm', 'rvs' => [{ 'n' => 'flag', 'v' => value }])
      expect(filter.accept?(alarm)).to be == (value == false)
    end
  end
end
