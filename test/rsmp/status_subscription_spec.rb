describe RSMP::SiteProxy do
  class SubscriptionProtocol
    attr_reader :messages

    def initialize
      @messages = []
    end

    def write_lines(line)
      @messages << JSON.parse(line)
    end
  end

  let(:protocol) { SubscriptionProtocol.new }
  let(:proxy) do
    supervisor = RSMP::Supervisor.new(log_settings: { 'active' => false })
    proxy = subject.new(supervisor: supervisor, protocol: protocol, site_id: 'TLC001')
    proxy.instance_variable_set(:@core_version, '3.3.0')
    proxy.instance_variable_set(:@state, :ready)
    proxy.instance_variable_set(:@site_settings, { 'timeouts' => { 'acknowledgement' => 1 } })
    proxy
  end
  let(:status_list) { [{ 'sCI' => 'S0001', 'n' => 'cyclecounter', 'uRt' => '1' }] }
  let(:unsubscribe_list) { status_list.map { |item| item.slice('sCI', 'n') } }
  let(:component) { proxy.find_component('C1') }

  def subscribe(list = status_list, component: 'C1')
    proxy.subscribe_to_status!(list, component: component, validate: false)
  end

  def unsubscribe(list = unsubscribe_list, component: 'C1')
    proxy.unsubscribe_to_status!(list, component: component, validate: false)
  end

  def subscriptions
    proxy.instance_variable_get(:@status_subscriptions)
  end

  def pending_unsubscriptions
    proxy.instance_variable_get(:@pending_status_unsubscriptions)
  end

  def acknowledge(message)
    proxy.process_ack(RSMP::MessageAck.new('oMId' => message.m_id))
  end

  def update
    RSMP::StatusUpdate.new(
      'cId' => 'C1',
      'sS' => [{ 'sCI' => 'S0001', 'n' => 'cyclecounter', 's' => 15, 'q' => 'recent' }]
    )
  end

  it 'accepts repeated periodic values until the matching unsubscribe ACK' do
    subscribe
    component.store_status(update)
    request = unsubscribe

    expect(protocol.messages.last['type']).to be == 'StatusUnsubscribe'
    component.check_repeat_values(update, subscriptions)

    proxy.process_ack(RSMP::MessageAck.new('oMId' => RSMP::Message.make_m_id))
    component.check_repeat_values(update, subscriptions)

    acknowledge(request)
    expect(subscriptions).to be == {}
    expect(pending_unsubscriptions).to be == {}
    expect do
      component.check_repeat_values(update, subscriptions)
    end.to raise_exception(RSMP::RepeatedStatusError)
  end

  it 'removes only the acknowledged attributes and component' do
    subscribe(status_list + [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 'uRt' => '1' }])
    subscribe(component: 'C2')
    acknowledge(unsubscribe)

    expect(subscriptions['C1']['S0001'].keys).to be == ['signalgroupstatus']
    expect(subscriptions['C2']['S0001'].keys).to be == ['cyclecounter']
  end

  it 'preserves subscriptions when the peer rejects the unsubscribe' do
    subscribe
    request = unsubscribe
    proxy.process_not_ack(RSMP::MessageNotAck.new('oMId' => request.m_id, 'rea' => 'Rejected'))

    expect(pending_unsubscriptions).to be == {}
    expect(subscriptions.dig('C1', 'S0001', 'cyclecounter', 'uRt')).to be == '1'
    acknowledge(request) # A late ACK after rejection is unknown.
    expect(subscriptions.dig('C1', 'S0001', 'cyclecounter', 'uRt')).to be == '1'
  end

  it 'preserves subscriptions on acknowledgement timeout' do
    acknowledge(subscribe)
    request = unsubscribe

    result = proxy.check_ack_timeout(request.timestamp + 2)

    expect(result.failure.code).to be == :missing_acknowledgement
    expect(subscriptions.dig('C1', 'S0001', 'cyclecounter', 'uRt')).to be == '1'
  end

  it 'preserves subscriptions when sending fails' do
    subscribe
    protocol.define_singleton_method(:write_lines) { |_line| raise IOError, 'closed' }

    result = proxy.unsubscribe_to_status(unsubscribe_list, component: 'C1', validate: false)

    expect(result.failure.code).to be == :disconnected
    expect(pending_unsubscriptions).to be == {}
    expect(subscriptions.dig('C1', 'S0001', 'cyclecounter', 'uRt')).to be == '1'
  end

  it 'discards pending unsubscribe state when sending raises' do
    subscribe
    protocol.define_singleton_method(:write_lines) { |_line| raise ArgumentError, 'write defect' }

    expect { unsubscribe }.to raise_exception(ArgumentError)

    expect(pending_unsubscriptions).to be == {}
    expect(subscriptions.dig('C1', 'S0001', 'cyclecounter', 'uRt')).to be == '1'
  end

  it 'discards pending unsubscribe state when the connection session is cleared' do
    subscribe
    request = unsubscribe
    expect(pending_unsubscriptions.keys).to be == [request.m_id]

    proxy.clear

    expect(pending_unsubscriptions).to be == {}
    acknowledge(request)
    expect(subscriptions.dig('C1', 'S0001', 'cyclecounter', 'uRt')).to be == '1'
  end

  it 'does not remove an identical resubscription when an older unsubscribe is acknowledged' do
    subscribe
    request = unsubscribe
    subscribe
    acknowledge(request)

    expect(subscriptions.dig('C1', 'S0001', 'cyclecounter', 'uRt')).to be == '1'
    acknowledge(unsubscribe)
    expect(subscriptions).to be == {}
  end

  it 'keeps a new subscription made after an unsubscribe for an absent attribute' do
    request = unsubscribe
    subscribe
    acknowledge(request)

    expect(subscriptions.dig('C1', 'S0001', 'cyclecounter', 'uRt')).to be == '1'
  end

  it 'cleans up disconnected subscriptions without sending a message' do
    subscribe
    protocol.messages.clear
    proxy.instance_variable_set(:@state, :disconnected)

    expect(unsubscribe).to be_nil
    expect(subscriptions).to be == {}
    expect(protocol.messages).to be == []
  end

  it 'still rejects unchanged values for an on-change subscription while unsubscribe is pending' do
    subscribe([{ 'sCI' => 'S0001', 'n' => 'cyclecounter', 'uRt' => '0', 'sOc' => true }])
    component.store_status(update)
    unsubscribe

    expect do
      component.check_repeat_values(update, subscriptions)
    end.to raise_exception(RSMP::RepeatedStatusError)
  end
end
