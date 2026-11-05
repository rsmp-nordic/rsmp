require_relative '../support/proxy_helper'

describe 'SXL testing hints' do
  include ProxyHelper

  let(:site) { build_site(core_version: '3.2.2', 'sxls' => { 'tlc' => ['1.2.1', '1.0.15', '1.2.0'] }) }
  let(:proxy) { new_connection(site) }

  def new_connection(site, port: 12_345)
    connection = build_supervisor_proxy(site, core_version: nil, port: port, state: :connected,
                                              version_determined: false, session_closed: false)
    connection.start_handshake
    connection
  end

  def reconnect(connection)
    connection.begin_session
    configure_proxy(connection, core_version: nil, state: :connected, version_determined: false)
    connection.start_handshake
  end

  def reject(connection, reason, id: nil)
    id ||= messages(connection).find { |item| item['type'] == 'Version' }['mId']
    message = RSMP::MessageNotAck.new('oMId' => id, 'rea' => reason)
    connection.process_packet(JSON.generate(message.attributes))
  end

  it 'starts with the first version and retains allowed hints without changing configuration' do
    expect(messages(proxy).first['SXL']).to be == '1.2.1'
    reject(proxy, 'Unsupported SXL; hint: 1.0.15')
    expect(proxy.disconnected?).to be == true
    reconnect(proxy)
    expect(messages(proxy).first['SXL']).to be == '1.0.15'
    expect(site.sxl_version).to be == '1.2.1'

    reject(proxy, 'No hint this time')
    reconnect(proxy)
    expect(messages(proxy).first['SXL']).to be == '1.0.15'

    proxy.disconnect
    reconnect(proxy)
    expect(messages(proxy).first['SXL']).to be == '1.0.15'
    reject(proxy, 'hint: 1.2.0')
    reconnect(proxy)
    expect(messages(proxy).first['SXL']).to be == '1.2.0'
  end

  it 'isolates selections by supervisor and restores defaults for a new site instance' do
    reject(proxy, 'hint: 1.0.15')
    expect(messages(new_connection(site)).first['SXL']).to be == '1.0.15'
    expect(messages(new_connection(site, port: 12_346)).first['SXL']).to be == '1.2.1'
    fresh = build_site(core_version: '3.2.2', 'sxls' => { 'tlc' => ['1.2.1', '1.0.15'] })
    expect(messages(new_connection(fresh)).first['SXL']).to be == '1.2.1'
  end

  it 'ignores missing, malformed, ambiguous and unlisted hints after a successful switch' do
    reject(proxy, 'hint: 1.0.15')
    ['No hint', 'thint: 1.2.0', '_hint: 1.2.0', 'hint: 1..2.1.3.3.4',
     'hint: 1.2', 'hint: 1.2.0suffix', 'hint: 1.2.0.1', 'hint: 9.0.0',
     'hint: tlc:1.2.0', 'hint: vms:1.2.0', 'hint: 1.2.0; hint: 1.2.1'].each do |reason|
      reconnect(proxy)
      reject(proxy, reason)
      reconnect(proxy)
      expect(messages(proxy).first['SXL']).to be == '1.0.15'
    end
  end

  it 'recognizes hint tokens after punctuation at a word boundary' do
    reject(proxy, 'Rejected SXL:hint: 1.0.15')
    reconnect(proxy)
    expect(messages(proxy).first['SXL']).to be == '1.0.15'
  end

  it 'retains server-site selections when the supervisor reconnects from a different source port' do
    server = build_site(core_version: '3.2.2', 'connection_role' => 'server', 'port' => 13_111,
                        'sxls' => { 'tlc' => ['1.2.1', '1.0.15'] })
    connection = new_connection(server)
    reject(connection, 'hint: 1.0.15')
    replacement = new_connection(server, port: 12_346)
    expect(messages(replacement).first['SXLS']).to be == [{ 'name' => 'tlc', 'version' => '1.0.15' }]
  end

  it 'ignores hints when the initial request offers Core 3.3, including mixed-version offers' do
    %w[3.3.0 all].each do |core|
      modern = build_site(core_version: core, 'sxls' => { 'tlc' => ['1.2.1', '1.0.15'] })
      connection = new_connection(modern)
      reject(connection, 'hint: 1.0.15')
      reconnect(connection)
      expect(messages(connection).first['SXLS']).to be == [{ 'name' => 'tlc', 'version' => '1.2.1' }]
    end
  end

  it 'ignores hints for a fixed version' do
    fixed = build_site(core_version: '3.2.2', 'sxls' => { 'tlc' => '1.2.1' })
    connection = new_connection(fixed)
    reject(connection, 'hint: 1.0.15')
    reconnect(connection)
    expect(messages(connection).first['SXL']).to be == '1.2.1'
  end

  it 'ignores hints for unknown, stale, acknowledged and unrelated messages' do
    old_id = messages(proxy).first['mId']
    reconnect(proxy)
    reject(proxy, 'hint: 1.0.15', id: old_id)
    expect(proxy.connected?).to be == true

    request_id = messages(proxy).first['mId']
    proxy.process_ack(RSMP::MessageAck.new('oMId' => request_id))
    reject(proxy, 'hint: 1.0.15', id: request_id)
    expect(proxy.connected?).to be == true

    watchdog = RSMP::Watchdog.new
    proxy.send_message(watchdog, validate: false)
    reject(proxy, 'hint: 1.0.15', id: watchdog.m_id)
    expect(proxy.connected?).to be == true
    reconnect(proxy)
    expect(messages(proxy).first['SXL']).to be == '1.2.1'
  end

  it 'ignores initial Version hints once the handshake has selected a version' do
    proxy.instance_variable_set(:@version_determined, true)
    reject(proxy, 'hint: 1.0.15')
    expect(proxy.connected?).to be == true
    reconnect(proxy)
    expect(messages(proxy).first['SXL']).to be == '1.2.1'
  end

  it 'clears buffered messages and subscriptions when changing SXL version' do
    proxy.instance_variable_set(:@message_buffer, [:old_message])
    proxy.instance_variable_set(:@status_subscriptions, { 'C1' => {} })
    reject(proxy, 'hint: 1.0.15')
    expect(proxy.message_buffer).to be == []
    expect(proxy.instance_variable_get(:@status_subscriptions)).to be == {}
  end

  it 'preserves buffered messages when a rejection does not change SXL version' do
    ['No hint', 'hint: 1.2.1', 'hint: 9.0.0'].each do |reason|
      reconnect(proxy)
      proxy.instance_variable_set(:@message_buffer, [:retained_message])
      reject(proxy, reason)
      expect(proxy.message_buffer).to be == [:retained_message]
    end
  end

  it 'accepts every configured supervisor version and sorts 3.3 mismatch diagnostics' do
    connection = build_site_proxy(core_version: '3.3.0', settings: { 'sxls' => { 'tlc' => ['1.2.1', '1.0.15'] } })
    connection.setup_site_settings
    expect(connection.select_sxl('name' => 'tlc', 'version' => '1.0.15')).to be == {
      'name' => 'tlc', 'status' => 'ok', 'version' => '1.0.15'
    }
    expect(connection.select_sxl('name' => 'tlc', 'version' => '1.2.0')).to be == {
      'name' => 'tlc', 'status' => 'mismatch', 'supported' => ['1.0.15', '1.2.1']
    }
  end
end
