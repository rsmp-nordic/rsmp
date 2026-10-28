require_relative '../support/proxy_helper'

describe RSMP::SiteProxy do
  include ProxyHelper

  let(:core_version) { '3.3.0' }
  let(:protocol) { ProxyHelper::CapturingProtocol.new }
  let(:proxy) do
    build_site_proxy(core_version: core_version, protocol: protocol, version_determined: false,
                     site_settings: { 'timeouts' => { 'acknowledgement' => 1 } })
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

  it 'keeps periodic settings until the matching unsubscribe ACK and accepts updates afterwards' do
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
    component.check_repeat_values(update, subscriptions)
  end

  it 'accepts repeated buffered values even with a known change-only subscription' do
    subscribe([{ 'sCI' => 'S0001', 'n' => 'cyclecounter', 'uRt' => '0', 'sOc' => true }])
    protocol.messages.clear
    buffered = update
    buffered.attributes['sS'].first['q'] = 'old'

    2.times { proxy.process_status_update(buffered) }

    expect(protocol.messages.map { |message| message['type'] }).to be == %w[MessageAck MessageAck]
    expect(component.statuses.dig('S0001', 'cyclecounter', 'q')).to be == 'old'
  end

  RSMP::Schema.core_versions.each do |version|
    with "Core #{version} fractional subscriptions" do
      let(:core_version) { version }

      it 'accepts repeated values when the subscription settings are unknown after reconnect' do
        # A new proxy has no subscription history, and older Core versions may
        # deliver buffered values without marking them old.
        expect(subscriptions).to be == {}
        2.times { proxy.process_status_update(update) }

        expect(protocol.messages.map { |message| message['type'] }).to be == %w[MessageAck MessageAck]
      end

      it 'accepts repeated values for fractional periodic subscriptions' do
        subscribe([{ 'sCI' => 'S0001', 'n' => 'cyclecounter', 'uRt' => '0.5' }])
        component.store_status(update)
        component.check_repeat_values(update, subscriptions)
        expect(component.update_rate_set?(subscriptions, 'S0001', 'cyclecounter')).to be == true
      end

      it 'still rejects unchanged values for change-only subscriptions' do
        subscribe([{ 'sCI' => 'S0001', 'n' => 'cyclecounter', 'uRt' => '0' }])
        component.store_status(update)
        expect do
          component.check_repeat_values(update, subscriptions)
        end.to raise_exception(RSMP::RepeatedStatusError)
      end

      %w[0.5 2.5].each do |interval|
        it "schedules periodic updates every #{interval} seconds" do
          site = RSMP::Site.new(
            site_settings: { 'core_version' => core_version, 'supervisors' => [],
                             'sxls' => { 'tlc' => '1.3.0' }, 'components' => { 'device' => { 'a' => {} } } },
            log_settings: { 'active' => false }
          )
          connection = RSMP::SupervisorProxy.new(site: site, ip: '127.0.0.1', port: 12_345, protocol: protocol)
          connection.instance_variable_set(:@core_version, core_version)
          connection.instance_variable_set(:@state, :ready)
          connection.instance_variable_set(:@version_determined, true)
          connection.build_sxl_interfaces
          site.components['a'].define_singleton_method(:get_status) { |*_args| %w[A recent] }
          arg = { 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 'uRt' => interval }
          arg['sOc'] = false if Gem::Version.new(core_version) >= Gem::Version.new('3.1.5')
          connection.process_status_subcribe(RSMP::StatusSubscribe.new('cId' => 'a', 'sS' => [arg]))
          subscription = connection.get_status_subscribe_interval('a', 'S0001', 'signalgroupstatus')
          start = subscription[:last_sent_at]
          period = interval.to_f
          expect(connection.status_updates_due(start + (period / 2))).to be == {}
          expect(connection.status_updates_due(start + period).keys).to be == ['a']
          expect(connection.status_updates_due(start + (period * 1.5))).to be == {}
          expect(connection.status_updates_due(start + (period * 2)).keys).to be == ['a']
        end
      end
    end
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

  with 'Core 3.3.0 subscription scheduling' do
    let(:core_version) { '3.3.0' }
    let(:site) do
      build_site(core_version: core_version, 'sxls' => { 'tlc' => '1.3.0' },
                 'components' => { 'device' => { 'a' => {}, 'b' => {} } })
    end

    it 'replies immediately to repeated subscriptions and keeps both scheduling options' do
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      component = site.components['a']
      component.define_singleton_method(:get_status) { |*_args| %w[A recent] }
      request = RSMP::StatusSubscribe.new('cId' => 'a', 'sS' => [
                                            { 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 'uRt' => '5', 'sOc' => true }
                                          ])
      2.times { proxy.process_status_subcribe(request) }
      expect(messages(proxy).map { |message| message['type'] }).to be ==
                                                                   %w[MessageAck StatusUpdate MessageAck StatusUpdate]
      subscription = proxy.get_status_subscribe_interval('a', 'S0001', 'signalgroupstatus')
      expect(subscription[:interval]).to be == 5
      expect(subscription[:on_change]).to be == true
      request.attributes['sS'].first.merge!('uRt' => '0', 'sOc' => false)
      expect { proxy.process_status_subcribe(request) }.to raise_exception(RSMP::MessageRejected)
    end

    it 'preserves fractional intervals when scheduling periodic updates' do
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      site.components['a'].define_singleton_method(:get_status) { |*_args| %w[A recent] }
      request = RSMP::StatusSubscribe.new('cId' => 'a', 'sS' => [
                                            { 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 'uRt' => '0.5', 'sOc' => false }
                                          ])
      proxy.process_status_subcribe(request)
      subscription = proxy.get_status_subscribe_interval('a', 'S0001', 'signalgroupstatus')
      expect(subscription[:interval]).to be_within(Float::EPSILON).of(0.5)
      start = subscription[:last_sent_at]
      expect(proxy.status_updates_due(start + 0.25)).to be == {}
      expect(proxy.status_updates_due(start + 0.5).keys).to be == ['a']
      expect(proxy.status_updates_due(start + 0.75)).to be == {}
      expect(proxy.status_updates_due(start + 1).keys).to be == ['a']
      request.attributes['sS'].first.merge!('uRt' => '-0.5', 'sOc' => true)
      expect { proxy.process_status_subcribe(request) }.to raise_exception(RSMP::MessageRejected)
      expect(proxy.get_status_subscribe_interval('a', 'S0001', 'signalgroupstatus')[:interval]).to be_within(Float::EPSILON).of(0.5)
    end

    it 'honors on-change alongside intervals and resets the interval after a change' do
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      proxy.define_singleton_method(:check_on_change_update) do |subscription, *_args|
        [42, subscription[:on_change]]
      end
      subscription = { interval: 5, on_change: true, last_sent_at: Time.at(0) }
      expect(proxy.check_status_subscription(subscription, nil, 'S0001', 'n', Time.at(2)).last).to be == true
      expect(subscription[:last_sent_at]).to be == Time.at(2)
      subscription[:on_change] = false
      expect(proxy.check_status_subscription(subscription, nil, 'S0001', 'n', Time.at(6)).last).to be == false
      expect(proxy.check_status_subscription(subscription, nil, 'S0001', 'n', Time.at(7)).last).to be == true
    end
  end
end
