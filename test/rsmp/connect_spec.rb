require_relative '../support/proxy_helper'
require_relative '../support/async_helper'

describe 'Connecting' do
  let(:config) do
    {
      timeout: 1,
      ip: 'localhost',
      port: 13_111,
      site_id: 'RN+SI0001',
      site_settings: {
        'site_id' => 'RN+SI0001',
        'supervisors' => [
          { 'ip' => 'localhost', 'port' => 13_111 }
        ]
      },
      supervisor_settings: {
        'port' => 13_111,
        'default' => { 'sxls' => { 'tlc' => RSMP::Schema.latest_version(:tlc) } }
      },
      log_settings: { 'active' => false }
    }
  end

  let(:site) do
    RSMP::Site.new(
      site_settings: config[:site_settings],
      log_settings: config[:log_settings]
    )
  end

  let(:supervisor) do
    RSMP::Supervisor.new(
      supervisor_settings: config[:supervisor_settings],
      log_settings: config[:log_settings]
    )
  end

  it 'works when the supervisor is started first' do
    expect(supervisor.proxies.size).to be == 0
    expect(site.proxies.size).to be == 1
    expect(site.proxies.first.state).to be == :disconnected

    with_async_context(context: lambda {
      supervisor.start
      supervisor.ready_condition.wait
      site.start
    }) do |_task|
      site_proxy = supervisor.wait_for_site! config[:site_id], timeout: config[:timeout]
      supervisor_proxy = site.wait_for_supervisor! config[:ip], timeout: config[:timeout]

      expect(site_proxy).to be_a(RSMP::SiteProxy)
      expect(supervisor_proxy).to be_a(RSMP::SupervisorProxy)

      expect(supervisor.proxies.size).to be == 1
      expect(site.proxies.size).to be == 1

      site_proxy.wait_for_state! :ready, timeout: config[:timeout]
      supervisor_proxy.wait_for_state! :ready, timeout: config[:timeout]

      expect(site_proxy.state).to be == :ready
      expect(supervisor_proxy.state).to be == :ready
    end
  end

  it 'works when the site is started first' do
    expect(supervisor.proxies.size).to be == 0
    expect(site.proxies.size).to be == 1
    expect(site.proxies.first.state).to be == :disconnected

    with_async_context(context: lambda {
      site.start
      supervisor.start
      supervisor.ready_condition.wait
    }) do |_task|
      site_proxy = supervisor.wait_for_site! config[:site_id], timeout: config[:timeout]
      supervisor_proxy = site.wait_for_supervisor! config[:ip], timeout: config[:timeout]

      expect(supervisor.proxies.size).to be == 1
      expect(site.proxies.size).to be == 1

      expect(site_proxy).to be_a(RSMP::SiteProxy)
      expect(supervisor_proxy).to be_a(RSMP::SupervisorProxy)

      site_proxy.wait_for_state! :ready, timeout: config[:timeout]
      supervisor_proxy.wait_for_state! :ready, timeout: config[:timeout]

      expect(site_proxy.state).to be == :ready
      expect(supervisor_proxy.state).to be == :ready
    end
  end

  it 'preserves two-part Core and SXL strings throughout a legacy connection' do
    config[:site_settings]['core_version'] = '3.2'
    config[:site_settings]['sxls'] = { 'tlc' => '1.2' }
    config[:supervisor_settings]['default']['core_version'] = '3.2'
    config[:supervisor_settings]['default']['sxls'] = { 'tlc' => '1.2' }

    with_async_context(context: lambda {
      supervisor.start
      supervisor.ready_condition.wait
      site.start
    }) do |_task|
      site_proxy = supervisor.wait_for_site! config[:site_id], timeout: config[:timeout]
      supervisor_proxy = site.wait_for_supervisor! config[:ip], timeout: config[:timeout]

      site_proxy.wait_for_state! :ready, timeout: config[:timeout]
      supervisor_proxy.wait_for_state! :ready, timeout: config[:timeout]

      expect(site_proxy.core_version).to be == '3.2.0'
      expect(supervisor_proxy.core_version).to be == '3.2.0'
      expect(site_proxy.core_version_string).to be == '3.2'
      expect(supervisor_proxy.core_version_string).to be == '3.2'
      expect(site_proxy.sxl_version).to be == '1.2'
      expect(supervisor_proxy.sxl_version).to be == '1.2'
    end
  end

  it 'works with a core-only 3.3.0 connection' do
    config[:site_settings]['core_version'] = '3.3.0'
    config[:site_settings]['sxls'] = {}
    config[:site_settings]['components'] = { 'device' => { 'sensor/1' => {} } }
    config[:site_settings]['send_after_connect'] = false
    config[:supervisor_settings]['default']['core_version'] = '3.3.0'
    config[:supervisor_settings]['default']['sxls'] = {}

    with_async_context(context: lambda {
      supervisor.start
      supervisor.ready_condition.wait
      site.start
    }) do |_task|
      site_proxy = supervisor.wait_for_site! config[:site_id], timeout: config[:timeout]
      supervisor_proxy = site.wait_for_supervisor! config[:ip], timeout: config[:timeout]

      site_proxy.wait_for_state! :ready, timeout: config[:timeout]
      supervisor_proxy.wait_for_state! :ready, timeout: config[:timeout]

      expect(site_proxy.accepted_sxls).to be == []
      expect(supervisor_proxy.accepted_sxls).to be == []
      expect(site_proxy.schemas).to be == { core: '3.3.0' }
      expect(supervisor_proxy.schemas).to be == { core: '3.3.0' }
      expect(site.main).to be_nil
      expect(site_proxy.site_aggregated_status).to be == Array.new(8, false)
      exchange = site_proxy.request_aggregated_status_and_collect!(within: config[:timeout])
      expect(exchange.request.attributes.key?('cId')).to be == false
    end
  end

  %w[3.1.2 3.1.3 3.1.4 3.1.5 3.2.0 3.2.1 3.2.2].each do |version|
    it "preserves the legacy handshake for Core #{version}" do
      config[:site_settings]['core_version'] = version
      config[:site_settings]['sxls'] = { 'tlc' => '1.2.1' }
      config[:supervisor_settings]['default']['core_version'] = version
      config[:supervisor_settings]['default']['sxls'] = { 'tlc' => '1.2.1' }
      with_async_context(context: lambda {
        supervisor.start
        supervisor.ready_condition.wait
        site.start
      }) do |_task|
        peer = supervisor.wait_for_site!(config[:site_id], timeout: config[:timeout])
        remote = site.wait_for_supervisor!(config[:ip], timeout: config[:timeout])
        peer.wait_for_state!(:ready, timeout: config[:timeout])
        remote.wait_for_state!(:ready, timeout: config[:timeout])
        expect(peer.core_version).to be == version
        expect(peer.site_aggregated_status).to be_nil
        expect(remote.core_version).to be == version
      end
    end
  end

  it 'builds proxies for reversed client/server roles' do
    config[:port] = 13_112
    config[:site_settings]['connection_role'] = 'server'
    config[:site_settings]['ip'] = '127.0.0.1'
    config[:site_settings]['port'] = config[:port]
    config[:site_settings]['core_version'] = '3.3.0'
    config[:supervisor_settings]['connection_role'] = 'client'
    config[:supervisor_settings]['sites'] = {
      config[:site_id] => {
        'core_version' => '3.3.0',
        'sxls' => { 'tlc' => RSMP::Schema.latest_version(:tlc) },
        'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => config[:port] }]
      }
    }

    expect(site.proxies).to be == []
    supervisor.send(:build_outbound_proxies)

    expect(supervisor.proxies.size).to be == 1
    expect(supervisor.proxies.first).to be_a(RSMP::SiteProxy)
    expect(supervisor.proxies.first.site_id).to be == config[:site_id]
  end

  it 'stores useAlarms false from a 3.3.0 Version response' do
    config[:site_settings]['core_version'] = '3.3.0'
    config[:site_settings]['components'] = { 'device' => { 'sensor/1' => {} } }
    config[:supervisor_settings]['default']['core_version'] = '3.3.0'
    config[:supervisor_settings]['default']['use_alarms'] = false

    with_async_context(context: lambda {
      supervisor.start
      supervisor.ready_condition.wait
      site.start
    }) do |_task|
      supervisor_proxy = site.wait_for_supervisor! config[:ip], timeout: config[:timeout]
      supervisor_proxy.wait_for_state! :ready, timeout: config[:timeout]

      expect(supervisor_proxy.use_alarms?).to be == false
    end
  end

  with 'Core 3.3.0 handshake' do
    include ProxyHelper

    let(:core_version) { '3.3.0' }
    let(:site) do
      build_site(core_version: core_version, 'sxls' => { 'tlc' => '1.3.0' },
                 'components' => { 'device' => { 'a' => {}, 'b' => {} } })
    end

    it 'allows the supervisor to become ready after rejecting the initial status' do
      proxy = build_site_proxy(core_version: core_version, state: :connected,
                               component_list_received: true, outgoing_watchdog_acknowledged: true)
      proxy.define_singleton_method(:start_watchdog) { nil }
      bits = Array.new(8, false)
      bits[5] = true
      status = RSMP::AggregatedStatus.new('aSTS' => RSMP::Clock.to_s, 'se' => bits)
      expect(proxy.process_packet(JSON.generate(status.attributes)).failure?).to be == true
      expect(messages(proxy).last['type']).to be == 'MessageNotAck'
      expect(proxy.ready?).to be == true
      expect(proxy.site_aggregated_status).to be_nil
    end

    it 'completes the site handshake on either acknowledgement of the initial status only' do
      [RSMP::MessageAck, RSMP::MessageNotAck].each do |klass|
        proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
        proxy.instance_variable_set(:@state, :connected)
        completions = []
        proxy.define_singleton_method(:handshake_complete) do
          completions << true
          self.state = :ready
        end
        proxy.component_list_acknowledged
        initial = messages(proxy).last
        expect(initial['type']).to be == 'AggregatedStatus'
        expect(proxy.ready?).to be == false
        proxy.process_ack(RSMP::MessageAck.new('oMId' => RSMP::Message.make_m_id))
        expect(completions).to be == []
        ack = klass.new('oMId' => initial['mId'], 'rea' => 'test')
        klass == RSMP::MessageAck ? proxy.process_ack(ack) : proxy.process_not_ack(ack)
        expect(completions).to be == [true]
        proxy.component_list_acknowledged
        expect(completions).to be == [true]
      end
    end

    it 'sends component and site status changes made while the initial status awaits acknowledgement' do
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      site.instance_variable_set(:@proxies, [proxy])
      proxy.instance_variable_set(:@state, :connected)
      proxy.define_singleton_method(:start_watchdog) { nil }
      proxy.send_component_list
      proxy.component_list_acknowledged
      initial = messages(proxy).last
      site.components['a'].update_metadata(name: 'Updated during handshake')
      site.components['a'].set_aggregated_status(:local_control)
      expect(messages(proxy).size).to be == 2
      proxy.process_ack(RSMP::MessageAck.new('oMId' => initial['mId']))
      expect(proxy.ready?).to be == true
      updates = messages(proxy).last(2)
      expect(updates.map { |message| message['type'] }).to be == %w[ComponentList AggregatedStatus]
      expect(updates.first['components'].first['name']).to be == 'Updated during handshake'
      expect(updates.last['se'][0]).to be == true
    end
  end
end
