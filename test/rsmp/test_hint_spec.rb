require_relative '../support/proxy_helper'

describe RSMP::TestHint do
  include ProxyHelper

  let(:scenario) { 'M0002.set_plan' }

  def build_hint_receiver(core_version: '3.2.2', enabled: true, state: :ready, sxls: [{ 'name' => 'tlc', 'version' => '1.2.1' }], main: true)
    proxy = build_site_proxy(core_version: core_version, state: state, site_settings: { 'test_hints' => enabled }, accepted_sxls: sxls)
    proxy.build_sxl_interfaces
    proxy.setup_components('main' => { 'TC' => nil }) if main
    proxy
  end

  it 'sends a schema-valid standalone hint without waiting for an acknowledgement' do
    %w[3.1.2 3.2.2 3.3.0].each do |core|
      site = build_site(core_version: core)
      proxy = build_supervisor_proxy(site, core_version: core)
      message = proxy.send_test_hint!(scenario)
      expect(messages(proxy).last.slice('type', 'oMId', 'rea')).to be == {
        'type' => 'MessageNotAck',
        'oMId' => '00000000-0000-4000-8000-000000000000',
        'rea' => 'test: {"scenario":"M0002.set_plan"}'
      }
      expect(message.original).to be_nil
      expect(proxy.instance_variable_get(:@awaiting_acknowledgement)).to be == {}
    end
  end

  it 'does not send or buffer a hint before the connection is ready' do
    site = build_site(core_version: '3.2.2')
    proxy = build_supervisor_proxy(site, core_version: '3.2.2', state: :disconnected)
    expect(proxy.send_test_hint(scenario).failure.code).to be == :not_ready
    expect(messages(proxy)).to be == []
  end

  it 'ignores malformed payloads and unrelated acknowledgements' do
    [nil, 'test: {', 'test: []', 'test: null', 'test: {"scenario":42}', 'hint: 1.2.1'].each do |reason|
      message = RSMP::MessageNotAck.new('oMId' => subject::ORIGINAL_MESSAGE_ID, 'rea' => reason)
      expect(subject.scenario(message)).to be_nil
    end
    message = subject.build(scenario)
    message.attributes['oMId'] = SecureRandom.uuid
    expect(subject.scenario(message)).to be_nil
  end

  it 'only runs recognized scenarios when explicitly enabled on a ready connection' do
    [[false, :ready], [nil, :ready], [true, :connected], [true, :ready]].each do |enabled, state|
      proxy = build_hint_receiver(enabled: enabled, state: state)
      proxy.process_not_ack(subject.build(scenario))
      expect(messages(proxy).map { |m| m['type'] }).to be == (enabled && state == :ready ? ['CommandRequest'] : [])
    end
  end

  it 'sends the subscription settings supported by the negotiated Core version' do
    { '3.1.4' => {}, '3.1.5' => { 'sOc' => false } }.each do |core, settings|
      proxy = build_hint_receiver(core_version: core)
      proxy.process_not_ack(subject.build('S0014.subscribe_once'))
      expect(messages(proxy).last.slice('type', 'cId', 'sS')).to be == {
        'type' => 'StatusSubscribe', 'cId' => 'TC',
        'sS' => [{ 'sCI' => 'S0014', 'n' => 'status', 'uRt' => '1' }.merge(settings)]
      }
    end
  end

  it 'ignores TLC scenarios on Core-only connections and connections without a main component' do
    [{ sxls: [] }, { main: false }].each do |options|
      proxy = build_hint_receiver(core_version: '3.3.0', **options)
      [scenario, 'S0014.subscribe_once'].each { |id| proxy.process_not_ack(subject.build(id)) }
      expect(messages(proxy)).to be == []
    end
  end

  it 'keeps normal rejection handling even with test hints enabled' do
    proxy = build_hint_receiver
    original = RSMP::Watchdog.new
    proxy.expect_acknowledgement(original)
    message = subject.build(scenario)
    message.attributes['oMId'] = original.m_id
    proxy.process_not_ack(message)
    expect(message.original).to be == original
    expect(proxy.instance_variable_get(:@acknowledgements)[original.m_id]).to be == message
    expect(proxy.instance_variable_get(:@awaiting_acknowledgement)).to be == {}
    expect(messages(proxy)).to be == []
  end

  it 'ignores unknown scenarios without issuing a command' do
    proxy = build_hint_receiver
    proxy.process_not_ack(subject.build('unknown.scenario'))
    expect(messages(proxy)).to be == []
  end
end
