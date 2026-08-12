require 'stringio'
require 'timecop'
require 'tmpdir'
require 'fileutils'
require 'openssl'
require 'edhoc'

describe RSMP::Secure do
  class SecureMemoryStream
    attr_reader :written

    def initialize(input = ''.b)
      @input = StringIO.new(input.b)
      @written = ''.b
    end

    def write(data)
      @written << data.b
      data.bytesize
    end

    def flush; end

    def closed?
      false
    end

    def read(size)
      @input.read(size)
    end

    def read_exactly(size)
      data = @input.read(size)
      raise EOFError if data.nil? || data.bytesize < size

      data
    end
  end

  def write_secure_file(dir, name, bytes)
    path = File.join(dir, name)
    File.binwrite(path, bytes)
    File.chmod(0o600, path) if name.include?('private')
    path
  end

  def generated_secure_identity(id)
    key = OpenSSL::PKey.generate_key('ED25519')

    secure_identity_hash(id, key.raw_private_key + key.raw_public_key, key.raw_public_key)
  end

  def secure_identity_hash(id, private_key, public_key)
    {
      private_key: private_key,
      public_key: public_key,
      credential: secure_credential(id, private_key: private_key, public_key: public_key)
    }
  end

  def vector_secure_identity(vector, id, role)
    secure_identity_hash(
      id,
      vector.fetch(:"#{role}_private_key"),
      vector.fetch(:"#{role}_public_key")
    )
  end

  def secure_settings(dir)
    vector = Edhoc::TestVector.suite0
    [site_secure_settings(dir, vector), supervisor_secure_settings(dir, vector)]
  end

  def site_secure_settings(dir, vector)
    {
      'private_key' => write_secure_file(dir, 'site-private.key', vector.fetch(:initiator_private_key)),
      'credential' => write_secure_file(dir, 'site.cred', vector_secure_credential(vector, :initiator, 'RN+SI0001')),
      'peers' => [supervisor_secure_peer(dir, vector)],
      'profile' => RSMP::Secure::PROFILE,
      'handshake_timeout' => 2
    }
  end

  def supervisor_secure_settings(dir, vector)
    {
      'private_key' => write_secure_file(dir, 'supervisor-private.key', vector.fetch(:responder_private_key)),
      'credential' => write_secure_file(dir, 'supervisor-local.cred',
                                        vector_secure_credential(vector, :responder, 'supervisor')),
      'peers' => [site_secure_peer(dir, vector)],
      'profile' => RSMP::Secure::PROFILE,
      'handshake_timeout' => 2
    }
  end

  def supervisor_secure_peer(dir, vector)
    {
      'id' => 'supervisor',
      'credential' => write_secure_file(dir, 'supervisor.cred',
                                        vector_secure_credential(vector, :responder, 'supervisor'))
    }
  end

  def site_secure_peer(dir, vector)
    {
      'id' => 'RN+SI0001',
      'credential' => write_secure_file(dir, 'site-peer.cred',
                                        vector_secure_credential(vector, :initiator, 'RN+SI0001'))
    }
  end

  def vector_secure_credential(vector, role, id)
    secure_credential(
      id,
      private_key: vector.fetch(:"#{role}_private_key"),
      public_key: vector.fetch(:"#{role}_public_key")
    )
  end

  def secure_credential(id, public_key:, **)
    RSMP::Secure::Credential.create(id: id, public_key: public_key)
  end

  def secure_channel_context
    RSMP::Secure::Channel.rsmp_context(
      profile: RSMP::Secure::PROFILE,
      initiator_id: 'RN+SI0001',
      responder_id: 'supervisor'
    )
  end

  def secure_identity(dir, name, private_key, credential)
    {
      'private_key' => write_secure_file(dir, "#{name}-private.key", private_key),
      'credential' => write_secure_file(dir, "#{name}.cred", credential),
      'handshake_timeout' => 2
    }
  end

  def secure_peer(dir, name, _public_key, credential)
    {
      'credential' => write_secure_file(dir, "#{name}-peer.cred", credential)
    }
  end

  def persisted_secure_identity(dir, name, identity)
    secure_identity(dir, name, identity.fetch(:private_key), identity.fetch(:credential))
  end

  def persisted_secure_peer(dir, name, identity)
    secure_peer(dir, name, identity.fetch(:public_key), identity.fetch(:credential))
  end

  def public_peer_settings(peer)
    {
      'id' => peer['id'],
      'credential' => peer['credential']
    }
  end

  def secure_site_node_settings(local, peer)
    {
      'site_id' => 'RN+SI0001',
      'sxls' => {},
      'supervisors' => [
        {
          'ip' => '127.0.0.1',
          'port' => 12_111,
          'secure' => public_peer_settings(peer)
        }
      ],
      'secure' => local.except('peers').merge('enabled' => true)
    }
  end

  def secure_supervisor_node_settings(local, peer)
    {
      'secure' => local.except('peers').merge('required' => true),
      'default' => {
        'sxls' => {}
      },
      'sites' => {
        'RN+SI0001' => {
          'sxls' => {},
          'secure' => public_peer_settings(peer)
        }
      }
    }
  end

  def multi_site_secure_settings(dir)
    vector = Edhoc::TestVector.suite0
    supervisor = vector_secure_identity(vector, 'supervisor', :responder)
    site1 = vector_secure_identity(vector, 'RN+SI0001', :initiator)
    site2 = generated_secure_identity('RN+SI0002')

    {
      supervisor: persisted_secure_identity(dir, 'supervisor', supervisor),
      site1: persisted_secure_identity(dir, 'site1', site1),
      site2: persisted_secure_identity(dir, 'site2', site2),
      supervisor_peer: persisted_secure_peer(dir, 'supervisor', supervisor),
      site1_peer: persisted_secure_peer(dir, 'site1', site1),
      site2_peer: persisted_secure_peer(dir, 'site2', site2)
    }
  end

  def multi_supervisor_secure_settings(dir)
    vector = Edhoc::TestVector.suite0
    site = vector_secure_identity(vector, 'RN+SI0001', :initiator)
    supervisor1 = vector_secure_identity(vector, 'supervisor1', :responder)
    supervisor2 = generated_secure_identity('supervisor2')

    {
      site: persisted_secure_identity(dir, 'site', site),
      supervisor1: persisted_secure_identity(dir, 'supervisor1', supervisor1),
      supervisor2: persisted_secure_identity(dir, 'supervisor2', supervisor2),
      site_peer: persisted_secure_peer(dir, 'site', site),
      supervisor1_peer: persisted_secure_peer(dir, 'supervisor1', supervisor1),
      supervisor2_peer: persisted_secure_peer(dir, 'supervisor2', supervisor2)
    }
  end

  def with_mocked_process_clock
    previous = Timecop.mock_process_clock?
    Timecop.mock_process_clock = true
    yield
  ensure
    Timecop.return
    Timecop.mock_process_clock = previous
  end

  def authorize_secure_pair(initiator, responder, core_version: '3.3.0')
    initiator.authorize!(rsmp_id: 'supervisor', core_version: core_version)
    responder.authorize!(rsmp_id: 'RN+SI0001', core_version: core_version)
  end

  it 'describes enabled secure settings for logs' do
    expect(RSMP::Secure.log_summary('enabled' => true)).to be == 'Secure profile rsmp-secure-v1'
    expect(RSMP::Secure.log_summary('required' => true)).to be == 'Secure profile rsmp-secure-v1'
    expect(RSMP::Secure.log_summary(nil)).to be_nil
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:status)).to be == :implemented
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:edhoc_cipher_suite)).to be == 4
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:edhoc_exporter_label)).to be == 32_768
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:edhoc_aead)).to be == 'ChaCha20-Poly1305'
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:data_protection)).to be == 'COSE_Encrypt0'
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:cose_algorithm)).to be == 24
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:credential_format)).to be(:include?, 'CCS')
    expect(RSMP::Secure.implemented_profile?('rsmp-secure-test-dev')).to be == false
    expect(RSMP::Secure.implemented_profile?('rsmp-secure-v1')).to be == true
    expect(RSMP::Secure.handshake_complete_summary({ 'enabled' => true }, role: :initiator)).to be == 'Secure handshake complete (initiator, epoch 0)'
    expect(RSMP::Secure.handshake_complete_summary({ 'enabled' => true }, role: :initiator, peer_id: 'RN+SI0002')).to be == 'Secure handshake with peer RN+SI0002 complete (initiator, epoch 0)'
    expect(RSMP::Secure.rekey_started_summary({ 'enabled' => true }, role: :initiator, epoch: 1)).to be == 'Secure rekey started (initiator, epoch 1)'
    expect(RSMP::Secure.rekey_started_summary({ 'enabled' => true }, role: :initiator, epoch: 1, peer_id: 'RN+SI0002')).to be == 'Secure rekey with peer RN+SI0002 started (initiator, epoch 1)'
    expect(RSMP::Secure.settings({})['rekey_after_messages']).to be == 1_000_000
    expect(RSMP::Secure.settings({})['rekey_after_bytes']).to be == 64 * 1024 * 1024 * 1024
    expect(RSMP::Secure.settings({})['rekey_after_seconds']).to be == 7_200
    expect(RSMP::Secure.settings({})['handshake_timeout']).to be == 2
    expect(RSMP::Secure.settings({})['rekey_timeout']).to be == 2
  end

  it 'disables decrypted secure payload logging by default' do
    expect(RSMP::Secure.settings({})['log_decrypted_payloads']).to be == false
  end

  it 'rate limits repeated failed secure connections by peer key' do
    now = 100.0
    limiter = RSMP::Secure::ConnectionRateLimiter.new(clock: -> { now })

    RSMP::Secure::ConnectionRateLimiter::MAX_FAILURES.times do
      limiter.check!('192.0.2.1')
      limiter.record_failure('192.0.2.1')
    end
    expect do
      limiter.check!('192.0.2.1')
    end.to raise_exception(RSMP::Secure::RateLimitError)
    expect(limiter.check!('192.0.2.2')).to be_nil

    logs = []
    settings = RSMP::Secure.with_runtime_policy(
      {},
      revocation_list: nil,
      rate_limiter: limiter,
      rate_limit_key: '192.0.2.1'
    )
    expect do
      RSMP::Secure.build_protocol(
        SecureMemoryStream.new,
        role: :responder,
        settings: settings,
        log: ->(message, options = {}) { logs << [message, options] }
      )
    end.to raise_exception(
      RSMP::HandshakeError,
      message: be == 'Secure RSMP connection temporarily rate limited'
    )
    expect(logs).to be == [['Secure handshake failed (category: rate_limit)', { level: :warning }]]

    now += RSMP::Secure::ConnectionRateLimiter::BLOCK_SECONDS + 1
    expect(limiter.check!('192.0.2.1')).to be_nil
  end

  it 'tracks and restores exact process-local credential revocations' do
    revocations = RSMP::Secure::RevocationList.new

    expect(revocations.revoke('RN+SI0001')).to be == true
    expect(revocations.revoke('RN+SI0001')).to be == false
    expect(revocations.revoked?('RN+SI0001')).to be == true
    expect(revocations.revoked?('RN+SI0002')).to be == false
    expect(revocations.restore('RN+SI0001')).to be == true
    expect(revocations.revoked?('RN+SI0001')).to be == false
  end

  it 'categorizes secure failure logs without exposing exception detail' do
    detail = RSMP::Secure::AuthenticationError.new('peer-controlled-sensitive-detail')
    summary = RSMP::Secure.failure_summary('authorization', detail)

    expect(summary).to be == 'Secure authorization failed (category: authentication)'
  end

  it 'redacts secure message payloads and payload-derived errors unless explicitly enabled' do
    protocol = Object.new
    protocol.define_singleton_method(:log_decrypted_payloads?) { false }
    archive = RSMP::Archive.new
    output = StringIO.new
    logger = RSMP::Logger.new('stream' => output, 'style' => false, 'json' => true, 'watchdogs' => true)
    target_class = Class.new do
      include RSMP::Logging

      def initialize(protocol, archive, logger)
        @protocol = protocol
        initialize_logging(archive: archive, logger: logger)
      end

      def author
        'secure-test'
      end
    end
    target = target_class.new(protocol, archive, logger)
    attributes = {
      'mType' => 'rSMsg',
      'type' => 'Watchdog',
      'mId' => 'secret-message-id',
      'wTs' => '2026-08-12T08:00:00.000Z'
    }
    message = RSMP::Message.build(attributes, JSON.generate(attributes))
    message.direction = :in

    exception = RuntimeError.new('secret-message-id')
    target.log('Received Watchdog secret-message-id', message: message, exception: exception)
    item = archive.items.last

    expect(item[:text]).to be == 'Received secure RSMP Watchdog (payload redacted)'
    expect(item[:exception]).to be_nil
    expect(item[:message].type).to be == 'Watchdog'
    expect(item[:message].direction).to be == :in
    expect(item[:message].attributes).to be == {}
    expect(item[:message].m_id).to be_nil
    expect(item[:message].json).to be_nil
    expect(output.string).to be(:include?, 'Received secure RSMP Watchdog (payload redacted)')
    expect(output.string).not.to be(:include?, 'secret-message-id')

    unknown = RSMP::Message.build(attributes.merge('type' => 'secret-type-value'), nil)
    unknown.direction = :in
    target.log('Received secret-type-value', message: unknown)
    expect(archive.items.last[:message].type).to be == 'Unknown'
    expect(output.string).not.to be(:include?, 'secret-type-value')
  end

  it 'retains decrypted secure payloads when logging is explicitly enabled' do
    protocol = Object.new
    protocol.define_singleton_method(:log_decrypted_payloads?) { true }
    archive = RSMP::Archive.new
    output = StringIO.new
    logger = RSMP::Logger.new('stream' => output, 'style' => false, 'json' => true, 'watchdogs' => true)
    target_class = Class.new do
      include RSMP::Logging

      def initialize(protocol, archive, logger)
        @protocol = protocol
        initialize_logging(archive: archive, logger: logger)
      end

      def author
        'secure-test'
      end
    end
    target = target_class.new(protocol, archive, logger)
    attributes = {
      'mType' => 'rSMsg',
      'type' => 'Watchdog',
      'mId' => 'development-message-id',
      'wTs' => '2026-08-12T08:00:00.000Z'
    }
    message = RSMP::Message.build(attributes, JSON.generate(attributes))
    message.direction = :in

    target.log('Received Watchdog development-message-id', message: message)
    item = archive.items.last

    expect(item[:text]).to be == 'Received Watchdog development-message-id'
    expect(item[:message]).to be(:equal?, message)
    expect(item[:message].attributes).to be == attributes
    expect(output.string).to be(:include?, 'development-message-id')
  end

  it 'rejects unsupported secure profiles with a clear error' do
    expect do
      RSMP::Secure.validate_profile_name!('rsmp-secure-unknown')
    end.to raise_exception(RSMP::ConfigurationError,
                           message: be == 'Unsupported secure profile "rsmp-secure-unknown"')
  end

  it 'requires positive mandatory rekey limits no weaker than the profile maxima' do
    {
      'rekey_after_messages' => nil,
      'rekey_after_bytes' => RSMP::Secure::MAX_REKEY_AFTER_BYTES + 1,
      'rekey_after_seconds' => 2,
      'handshake_timeout' => 3,
      'rekey_timeout' => 1
    }.each do |key, value|
      expect do
        RSMP::Secure.validate_rekey_settings!(key => value)
      end.to raise_exception(RSMP::ConfigurationError)
    end
  end

  it 'rejects enabled-only security on a listening endpoint' do
    expect do
      RSMP::Secure.validate_transport_mode!({ 'enabled' => true }, connection_role: 'server')
    end.to raise_exception(
      RSMP::ConfigurationError,
      message: be == 'secure.enabled does not secure an inbound listener; use secure.required: true'
    )

    expect(
      RSMP::Secure.validate_transport_mode!({ 'required' => true }, connection_role: 'server')
    ).to be == true
    expect(
      RSMP::Secure.validate_transport_mode!({ 'enabled' => true }, connection_role: 'client')
    ).to be == true
  end

  it 'merges site endpoint secure settings with the local site identity' do
    local = {
      'enabled' => true,
      'private_key' => 'site-private.key',
      'credential' => 'site.cred'
    }
    endpoint = {
      'secure' => {
        'id' => 'supervisor-a',
        'credential' => 'supervisor.cred'
      }
    }

    merged = RSMP::Secure.site_peer_settings({ 'secure' => local }, endpoint)

    expect(merged['private_key']).to be == 'site-private.key'
    expect(merged['credential']).to be == 'site.cred'
    expect(merged['peers']).to be == [{
      'id' => 'supervisor-a',
      'credential' => 'supervisor.cred',
      RSMP::Secure::PEER_ID_KEY => 'supervisor-a',
      RSMP::Secure::RSMP_ID_KEY => 'supervisor-a',
      RSMP::Secure::RSMP_ROLE_KEY => 'supervisor'
    }]
  end

  it 'defaults site local identity paths from the active site id' do
    merged = RSMP::Secure.site_peer_settings(
      {
        'site_id' => 'RN+SI0002',
        'secure' => {
          'enabled' => true
        }
      },
      {
        'secure' => {
          'id' => 'supervisor'
        }
      }
    )

    expect(merged['private_key']).to be == 'secure/RN+SI0002.private.key'
    expect(merged['credential']).to be == 'secure/RN+SI0002.cred'
    expect(merged['peers']).to be == [{
      'id' => 'supervisor',
      'credential' => 'secure/supervisor.cred',
      RSMP::Secure::PEER_ID_KEY => 'supervisor',
      RSMP::Secure::RSMP_ID_KEY => 'supervisor',
      RSMP::Secure::RSMP_ROLE_KEY => 'supervisor'
    }]
  end

  it 'defaults supervisor local identity and site peer paths by convention' do
    settings = RSMP::Secure.supervisor_inbound_settings(
      'secure' => {
        'required' => true
      },
      'sites' => {
        'RN+SI0001' => {
          'sxls' => {}
        },
        'RN+SI0002' => {
          'sxls' => {}
        }
      }
    )

    expect(settings['private_key']).to be == 'secure/supervisor.private.key'
    expect(settings['credential']).to be == 'secure/supervisor.cred'
    expect(settings['peers']).to be == [
      {
        'id' => 'RN+SI0001',
        'credential' => 'secure/RN+SI0001.cred',
        RSMP::Secure::PEER_ID_KEY => 'RN+SI0001',
        RSMP::Secure::RSMP_ID_KEY => 'RN+SI0001',
        RSMP::Secure::RSMP_ROLE_KEY => 'site'
      },
      {
        'id' => 'RN+SI0002',
        'credential' => 'secure/RN+SI0002.cred',
        RSMP::Secure::PEER_ID_KEY => 'RN+SI0002',
        RSMP::Secure::RSMP_ID_KEY => 'RN+SI0002',
        RSMP::Secure::RSMP_ROLE_KEY => 'site'
      }
    ]
  end

  it 'does not imply supervisor site peers when secure is not required' do
    settings = RSMP::Secure.supervisor_inbound_settings(
      'secure' => {
        'enabled' => true
      },
      'sites' => {
        'RN+SI0001' => {
          'sxls' => {}
        },
        'RN+SI0002' => {
          'sxls' => {},
          'secure' => {}
        }
      }
    )

    expect(settings['peers']).to be == [{
      'id' => 'RN+SI0002',
      'credential' => 'secure/RN+SI0002.cred',
      RSMP::Secure::PEER_ID_KEY => 'RN+SI0002',
      RSMP::Secure::RSMP_ID_KEY => 'RN+SI0002',
      RSMP::Secure::RSMP_ROLE_KEY => 'site'
    }]
  end

  it 'defaults supervisor outbound peer paths from the configured site id' do
    settings = RSMP::Secure.supervisor_site_settings(
      {
        'secure' => {
          'enabled' => true
        }
      },
      {
        'secure' => {}
      },
      site_id: 'RN+SI0002'
    )

    expect(settings['private_key']).to be == 'secure/supervisor.private.key'
    expect(settings['credential']).to be == 'secure/supervisor.cred'
    expect(settings['peers']).to be == [{
      'id' => 'RN+SI0002',
      'credential' => 'secure/RN+SI0002.cred',
      RSMP::Secure::PEER_ID_KEY => 'RN+SI0002',
      RSMP::Secure::RSMP_ID_KEY => 'RN+SI0002',
      RSMP::Secure::RSMP_ROLE_KEY => 'site'
    }]
  end

  it 'fails site startup early when the local secure identity files are missing' do
    Dir.mktmpdir do |dir|
      expect do
        RSMP::Site.new(
          site_settings: {
            RSMP::Secure::CONFIG_DIR_KEY => dir,
            'site_id' => 'RN+SI0003',
            'sxls' => {},
            'secure' => {
              'enabled' => true
            }
          },
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == "secure.private_key file not found: #{File.join(dir, 'secure/RN+SI0003.private.key')}"
      )
    end
  end

  it 'fails supervisor startup early when the local secure identity files are missing' do
    Dir.mktmpdir do |dir|
      expect do
        RSMP::Supervisor.new(
          supervisor_settings: {
            RSMP::Secure::CONFIG_DIR_KEY => dir,
            'secure' => {
              'required' => true
            },
            'default' => {
              'sxls' => {}
            },
            'sites' => {}
          },
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == "secure.private_key file not found: #{File.join(dir, 'secure/supervisor.private.key')}"
      )
    end
  end

  it 'fails supervisor startup early when an implied secure peer file is missing' do
    Dir.mktmpdir do |dir|
      secure_dir = File.join(dir, 'secure')
      vector = Edhoc::TestVector.suite0
      FileUtils.mkdir_p(secure_dir)
      File.binwrite(File.join(secure_dir, 'supervisor.private.key'), vector.fetch(:responder_private_key))
      File.binwrite(File.join(secure_dir, 'supervisor.cred'),
                    vector_secure_credential(vector, :responder, 'supervisor'))

      expect do
        RSMP::Supervisor.new(
          supervisor_settings: {
            RSMP::Secure::CONFIG_DIR_KEY => dir,
            'secure' => {
              'required' => true
            },
            'default' => {
              'sxls' => {}
            },
            'sites' => {
              'RN+SI0001' => {
                'sxls' => {}
              }
            }
          },
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == "secure peer RN+SI0001 credential file not found: #{File.join(dir, 'secure/RN+SI0001.cred')}"
      )
    end
  end

  it 'fails startup before listening when a peer credential is not the exact CCS shape' do
    Dir.mktmpdir do |dir|
      _site_secure, supervisor_secure = secure_settings(dir)
      site_peer = supervisor_secure.fetch('peers').first
      File.binwrite(site_peer.fetch('credential'), RSMP::Secure::Cbor.encode('v' => 1))

      expect do
        RSMP::Supervisor.new(
          supervisor_settings: secure_supervisor_node_settings(supervisor_secure, site_peer),
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == 'invalid CCS credential: credential must contain exactly the Secure RSMP v1 fields'
      )
    end
  end

  it 'fails site startup when the private key has the wrong length' do
    Dir.mktmpdir do |dir|
      site_secure, = secure_settings(dir)
      supervisor_peer = site_secure.fetch('peers').first
      private_key = File.binread(site_secure.fetch('private_key'))
      File.binwrite(site_secure.fetch('private_key'), private_key.byteslice(0, 32))

      expect do
        RSMP::Site.new(
          site_settings: secure_site_node_settings(site_secure, supervisor_peer),
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == 'secure.private_key must contain a 64-byte Ed25519 private key'
      )
    end
  end

  it 'fails startup when a private-key file permits group or other access' do
    skip 'POSIX file permissions are not enforced on Windows' if Gem.win_platform?

    Dir.mktmpdir do |dir|
      vector = Edhoc::TestVector.suite0
      settings = site_secure_settings(dir, vector)
      File.chmod(0o644, settings.fetch('private_key'))

      expect do
        RSMP::Secure::Protocol.new(SecureMemoryStream.new, role: :initiator, settings: settings)
      end.to raise_exception(
        RSMP::Secure::ConfigurationError,
        message: be(:include?, 'permissions must deny group and other access')
      )
    end
  end

  it 'fails site startup when the private key public half does not match its private seed' do
    Dir.mktmpdir do |dir|
      site_secure, = secure_settings(dir)
      supervisor_peer = site_secure.fetch('peers').first
      private_key = File.binread(site_secure.fetch('private_key')).dup
      private_key.setbyte(0, private_key.getbyte(0) ^ 0x01)
      File.binwrite(site_secure.fetch('private_key'), private_key)

      expect do
        RSMP::Site.new(
          site_settings: secure_site_node_settings(site_secure, supervisor_peer),
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == 'secure.private_key public key does not match its private seed'
      )
    end
  end

  it 'fails supervisor startup when a peer CCS public key has the wrong length' do
    Dir.mktmpdir do |dir|
      _site_secure, supervisor_secure = secure_settings(dir)
      site_peer = supervisor_secure.fetch('peers').first
      credential = RSMP::Secure::Cbor.decode(File.binread(site_peer.fetch('credential')))
      credential.fetch(8).fetch(1)[-2] = credential.fetch(8).fetch(1).fetch(-2).byteslice(0, 31)
      File.binwrite(site_peer.fetch('credential'), RSMP::Secure::Cbor.encode(credential))

      expect do
        RSMP::Supervisor.new(
          supervisor_settings: secure_supervisor_node_settings(supervisor_secure, site_peer),
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == 'invalid CCS credential: credential public key must be 32 bytes'
      )
    end
  end

  it 'fails site startup when the private key does not match the local credential' do
    Dir.mktmpdir do |dir|
      site_secure, = secure_settings(dir)
      supervisor_peer = site_secure.fetch('peers').first
      attacker = generated_secure_identity('attacker')
      File.binwrite(site_secure.fetch('private_key'), attacker.fetch(:private_key))

      expect do
        RSMP::Site.new(
          site_settings: secure_site_node_settings(site_secure, supervisor_peer),
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == 'CCS credential "RN+SI0001" does not match private key'
      )
    end
  end

  it 'fails site startup when the local credential id does not match the site id' do
    Dir.mktmpdir do |dir|
      site_secure, = secure_settings(dir)
      supervisor_peer = site_secure.fetch('peers').first
      vector = Edhoc::TestVector.suite0
      File.binwrite(site_secure.fetch('credential'),
                    vector_secure_credential(vector, :initiator, 'RN+SI9999'))

      expect do
        RSMP::Site.new(
          site_settings: secure_site_node_settings(site_secure, supervisor_peer),
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == 'CCS credential "RN+SI9999" does not match local id "RN+SI0001"'
      )
    end
  end

  it 'fails supervisor startup when a peer credential id does not match its configured site' do
    Dir.mktmpdir do |dir|
      _site_secure, supervisor_secure = secure_settings(dir)
      site_peer = supervisor_secure.fetch('peers').first
      vector = Edhoc::TestVector.suite0
      File.binwrite(site_peer.fetch('credential'),
                    vector_secure_credential(vector, :initiator, 'RN+SI9999'))

      expect do
        RSMP::Supervisor.new(
          supervisor_settings: secure_supervisor_node_settings(supervisor_secure, site_peer),
          log_settings: { 'active' => false }
        )
      end.to raise_exception(
        RSMP::ConfigurationError,
        message: be == 'CCS credential "RN+SI9999" does not match peer id "RN+SI0001"'
      )
    end
  end

  it 'does not use top-level public peer credentials as a shortcut' do
    merged = RSMP::Secure.site_peer_settings(
      {
        'secure' => {
          'enabled' => true,
          'private_key' => 'site-private.key',
          'credential' => 'site.cred',
          'public_key' => 'legacy-supervisor.pub'
        }
      },
      {}
    )

    expect(merged['public_key']).to be_nil
    expect(merged['peers']).to be_nil
  end

  it 'builds supervisor inbound secure peers from configured sites' do
    settings = RSMP::Secure.supervisor_inbound_settings(
      'secure' => {
        'required' => true,
        'private_key' => 'supervisor-private.key',
        'credential' => 'supervisor.cred'
      },
      'sites' => {
        'RN+SI0001' => {
          'secure' => {
            'credential' => 'site1.cred'
          }
        },
        'RN+SI0002' => {
          'secure' => {
            'credential' => 'site2.cred'
          }
        }
      }
    )

    expect(settings['peers'].map { |peer| peer['id'] }).to be == %w[RN+SI0001 RN+SI0002]
  end

  it 'resolves secure file paths relative to the config file directory' do
    Dir.mktmpdir do |dir|
      vector = Edhoc::TestVector.suite0
      config_dir = File.join(dir, 'config')
      secure_dir = File.join(config_dir, 'secure')
      FileUtils.mkdir_p(secure_dir)

      private_key_path = File.join(secure_dir, 'RN+SI0001.private.key')
      File.binwrite(private_key_path, vector.fetch(:initiator_private_key))
      File.chmod(0o600, private_key_path)
      File.binwrite(File.join(secure_dir, 'RN+SI0001.cred'),
                    vector_secure_credential(vector, :initiator, 'RN+SI0001'))
      File.binwrite(File.join(secure_dir, 'supervisor.cred'),
                    vector_secure_credential(vector, :responder, 'supervisor'))

      config_path = File.join(config_dir, 'site.yaml')
      File.write(config_path, <<~YAML)
        site_id: RN+SI0001
        sxls: {}
        supervisors:
          - ip: 127.0.0.1
            port: 12111
            secure:
              id: supervisor
              credential: secure/supervisor.cred
        secure:
          enabled: true
          private_key: secure/RN+SI0001.private.key
          credential: secure/RN+SI0001.cred
      YAML

      settings = RSMP::Site::Options.load_file(config_path).to_h
      secure_settings = RSMP::Secure.site_peer_settings(settings, settings['supervisors'].first)
      protocol = RSMP::Secure::Protocol.new(SecureMemoryStream.new, role: :initiator, settings: secure_settings)

      expect(protocol.settings[RSMP::Secure::CONFIG_DIR_KEY]).to be == config_dir
    end
  end

  with 'CBOR encoding' do
    it 'roundtrips RSMP message attributes into the existing message model' do
      attributes = {
        'mType' => 'rSMsg',
        'type' => 'Watchdog',
        'mId' => 'f4b69bd8-fc54-4d1c-8c30-c929f21d27dd',
        'wTs' => '2026-03-17T10:15:30.000Z'
      }

      decoded = RSMP::Secure::Cbor.decode(RSMP::Secure::Cbor.encode(attributes))
      message = RSMP::Message.build(decoded, JSON.generate(decoded))

      expect(message).to be_a(RSMP::Watchdog)
      expect(message.attributes).to be == attributes
    end

    it 'rejects non-deterministic map ordering' do
      non_deterministic = "\xA2\x61b\x01\x61a\x02".b

      expect do
        RSMP::Secure::Cbor.decode(non_deterministic)
      end.to raise_exception(RSMP::Secure::FrameError)
    end

    it 'rejects duplicate raw CBOR map keys' do
      duplicate_keys = "\xA2\x61a\x01\x61a\x02".b

      expect do
        RSMP::Secure::Cbor.decode(duplicate_keys)
      end.to raise_exception(RSMP::Secure::FrameError)
    end
  end

  with RSMP::Secure::Credential do
    it 'encodes the exact deterministic v1 CCS credential' do
      vector = Edhoc::TestVector.suite0
      encoded = RSMP::Secure::Credential.create(
        id: 'RN+SI0001',
        public_key: vector.fetch(:initiator_public_key)
      )
      credential = RSMP::Secure::Credential.decode(encoded)
      kid = RSMP::Secure::Credential.kid(credential)

      expect(credential).to be == {
        2 => 'RN+SI0001',
        8 => {
          1 => {
            1 => 1,
            2 => kid,
            -1 => 6,
            -2 => vector.fetch(:initiator_public_key)
          }
        }
      }
      expect(kid).to be == Digest::SHA256.digest(vector.fetch(:initiator_public_key)).byteslice(0, 16)
      expect(encoded).to be == RSMP::Secure::Cbor.encode(credential)
    end

    it 'rejects unknown CCS fields and a KID not derived from the public key' do
      vector = Edhoc::TestVector.suite0
      encoded = RSMP::Secure::Credential.create(id: 'RN+SI0001', public_key: vector.fetch(:initiator_public_key))
      credential = RSMP::Secure::Cbor.decode(encoded)
      with_unknown_field = credential.merge(99 => true)
      wrong_kid = Marshal.load(Marshal.dump(credential))
      wrong_kid.fetch(8).fetch(1)[2] = "\0" * 16

      expect do
        RSMP::Secure::Credential.decode(RSMP::Secure::Cbor.encode(with_unknown_field))
      end.to raise_exception(RSMP::Secure::ConfigurationError,
                             message: be(:include?, 'exactly the Secure RSMP v1 fields'))
      expect do
        RSMP::Secure::Credential.decode(RSMP::Secure::Cbor.encode(wrong_kid))
      end.to raise_exception(RSMP::Secure::ConfigurationError,
                             message: be(:include?, 'kid does not match its public key'))
    end

    it 'rejects a private COSE key parameter in a provisioned credential' do
      vector = Edhoc::TestVector.suite0
      credential = RSMP::Secure::Cbor.decode(
        RSMP::Secure::Credential.create(id: 'RN+SI0001', public_key: vector.fetch(:initiator_public_key))
      )
      credential.fetch(8).fetch(1)[-4] = vector.fetch(:initiator_private_key).byteslice(0, 32)

      expect do
        RSMP::Secure::Credential.decode(RSMP::Secure::Cbor.encode(credential))
      end.to raise_exception(RSMP::Secure::ConfigurationError,
                             message: be(:include?, 'exactly the Secure RSMP v1 fields'))
    end
  end

  with RSMP::Secure::FrameIO do
    it 'writes and reads a length-prefixed CBOR frame' do
      write_stream = SecureMemoryStream.new
      writer = RSMP::Secure::FrameIO.new(write_stream, max_frame_size: 100)
      writer.write(
        'v' => 1,
        'type' => 'data',
        'ct' => 'abc'.b
      )

      reader = RSMP::Secure::FrameIO.new(SecureMemoryStream.new(write_stream.written), max_frame_size: 100)
      frame = reader.read

      expect(frame).to be == { 'ct' => 'abc'.b, 'type' => 'data', 'v' => 1 }
      expect(writer.traffic_stats.written_bytes).to be == write_stream.written.bytesize
      expect(writer.traffic_stats.written_frames).to be == 1
      expect(reader.traffic_stats.read_bytes).to be == write_stream.written.bytesize
      expect(reader.traffic_stats.read_frames).to be == 1
    end

    it 'rejects oversized frames' do
      bytes = [10].pack('N') + ('x' * 10)

      expect do
        RSMP::Secure::FrameIO.new(SecureMemoryStream.new(bytes), max_frame_size: 2).read
      end.to raise_exception(RSMP::Secure::FrameError)
    end

    it 'treats EOF before a frame as a clean peer disconnect' do
      expect do
        RSMP::Secure::FrameIO.new(SecureMemoryStream.new, max_frame_size: 100).read
      end.to raise_exception(EOFError, message: be(:==, 'Secure RSMP peer closed connection'))
    end

    it 'rejects truncated frame headers' do
      expect do
        RSMP::Secure::FrameIO.new(SecureMemoryStream.new("\x00\x01".b), max_frame_size: 100).read
      end.to raise_exception(RSMP::Secure::FrameError, message: be(:==, 'Truncated secure frame header'))
    end

    it 'rejects truncated frame payloads' do
      bytes = "#{[10].pack('N')}xx"

      expect do
        RSMP::Secure::FrameIO.new(SecureMemoryStream.new(bytes), max_frame_size: 100).read
      end.to raise_exception(RSMP::Secure::FrameError, message: be(:==, 'Truncated secure frame payload'))
    end

    it 'rejects invalid CBOR' do
      bytes = [1].pack('N') + "\xff".b

      expect do
        RSMP::Secure::FrameIO.new(SecureMemoryStream.new(bytes), max_frame_size: 100).read
      end.to raise_exception(RSMP::Secure::FrameError)
    end
  end

  with RSMP::Secure::Channel do
    it 'uses matching directional keys for initiator and responder' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: secure_channel_context)
      plaintext = RSMP::Secure::Cbor.encode('mType' => 'rSMsg', 'type' => 'Watchdog')

      frame = initiator.encrypt_payload(plaintext)

      expect(RSMP::Secure::Cbor.decode(responder.decrypt_frame(frame))).to be == {
        'mType' => 'rSMsg',
        'type' => 'Watchdog'
      }
    end

    it 'encodes data as untagged COSE_Encrypt0 with a protected algorithm and Partial IV' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))
      protected_headers, unprotected_headers, ciphertext = frame.fetch('enc')
      decoded_frame = RSMP::Secure::Cbor.decode(RSMP::Secure::Cbor.encode(frame))

      expect(frame.keys.sort).to be == %w[enc epoch type v]
      expect(RSMP::Secure::Cbor.decode(protected_headers)).to be == { 1 => 24 }
      expect(unprotected_headers).to be == { 6 => "\x01".b }
      expect(ciphertext.bytesize).to be > RSMP::Secure::CoseEncrypt0::TAG_BYTES
      expect(decoded_frame.fetch('enc').fetch(1)).to be == { 6 => "\x01".b }
    end

    it 'matches the Secure RSMP v1 COSE_Encrypt0 frame vector' do
      exporter_secret = (0...RSMP::Secure::Channel::EXPORTER_SECRET_BYTES).to_a.pack('C*')
      channel = RSMP::Secure::Channel.new(exporter_secret, role: :initiator,
                                                           rsmp_context: secure_channel_context)
      frame = channel.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))
      expected = 'a461760163656e638344a1011818a106410155226e57cab36897a36ff57752ee50718bc552376c5f' \
                 '647479706564646174616565706f636800'

      expect(RSMP::Secure::Cbor.encode(frame).unpack1('H*')).to be == expected
    end

    it 'uses minimal COSE Partial IVs and the RFC 9052 Context IV construction' do
      cose = RSMP::Secure::CoseEncrypt0

      expect(cose.encode_partial_iv(1)).to be == "\x01".b
      expect(cose.encode_partial_iv(255)).to be == "\xff".b
      expect(cose.encode_partial_iv(256)).to be == "\x01\x00".b
      expect(cose.nonce("\xaa".b * 8, "\x01".b)).to be == ("\xaa".b * 8) + "\x00\x00\x00\x01".b
      expect do
        cose.encode_partial_iv(1 << 32)
      end.to raise_exception(RSMP::Secure::FrameError)
    end

    it 'fails closed instead of wrapping an exhausted frame index' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: secure_channel_context)
      maximum = RSMP::Secure::Channel::MAX_SEQUENCE
      initiator.instance_variable_set(:@send_idx, maximum - 1)
      responder.instance_variable_set(:@recv_idx, maximum - 1)

      last_frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))
      expect(RSMP::Secure::CoseEncrypt0.sequence(last_frame.fetch('enc'))).to be == maximum
      expect(RSMP::Secure::Cbor.decode(responder.decrypt_frame(last_frame))).to be == { 'ok' => true }

      expect do
        initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => false))
      end.to raise_exception(
        RSMP::Secure::FrameError,
        message: be == "Secure frame index exhausted at #{maximum}; rekey or reconnect"
      )
      expect do
        responder.decrypt_frame(last_frame)
      end.to raise_exception(
        RSMP::Secure::FrameError,
        message: be == "Secure frame index exhausted at #{maximum}; rekey or reconnect"
      )
    end

    it 'uses a monotonic uint64 epoch and fails closed instead of wrapping it' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      channel = RSMP::Secure::Channel.new(secret, role: :initiator, epoch: 255,
                                                  rsmp_context: secure_channel_context)
      exhausted = RSMP::Secure::Channel.new(secret, role: :initiator,
                                                    epoch: RSMP::Secure::Channel::MAX_EPOCH,
                                                    rsmp_context: secure_channel_context)

      expect(channel.next_epoch).to be == 256
      expect do
        exhausted.next_epoch
      end.to raise_exception(
        RSMP::Secure::FrameError,
        message: be(:include?, 'Secure epoch exhausted')
      )
    end

    it 'tracks every protected frame and COSE ciphertext byte by direction' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: secure_channel_context)
      frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))

      responder.decrypt_frame(frame)

      expect(initiator.sent_frames).to be == 1
      expect(responder.received_frames).to be == 1
      expect(initiator.sent_ciphertext_bytes).to be == frame.fetch('enc').fetch(2).bytesize
      expect(responder.received_ciphertext_bytes).to be == frame.fetch('enc').fetch(2).bytesize
    end

    it 'binds the secure profile into traffic keys and AAD' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      context = RSMP::Secure::Channel.rsmp_context(
        profile: RSMP::Secure::PROFILE,
        initiator_id: 'RN+SI0001',
        responder_id: 'supervisor'
      )
      other_context = RSMP::Secure::Channel.rsmp_context(
        profile: 'rsmp-secure-test',
        initiator_id: 'RN+SI0001',
        responder_id: 'supervisor'
      )
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: context)
      responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: other_context)
      frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))

      expect do
        responder.decrypt_frame(frame)
      end.to raise_exception(RSMP::Secure::AuthenticationError)
    end

    it 'builds the implemented RSMP exporter context' do
      context = secure_channel_context

      expect(RSMP::Secure::Cbor.decode(context)).to be == {
        'connection' => {
          'socket' => 'single-rsmp-connection'
        },
        'context' => 'rsmp-secure-v1',
        'initiator' => 'RN+SI0001',
        'profile' => RSMP::Secure::PROFILE,
        'responder' => 'supervisor'
      }
    end

    it 'requires both authenticated identities in the exporter context' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      incomplete_context = RSMP::Secure::Cbor.encode(
        'context' => 'rsmp-secure-v1',
        'profile' => RSMP::Secure::PROFILE,
        'connection' => { 'socket' => RSMP::Secure::Channel::CONNECTION_ID }
      )

      expect do
        RSMP::Secure::Channel.new(secret, role: :initiator)
      end.to raise_exception(RSMP::Secure::ConfigurationError)
      expect do
        RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: incomplete_context)
      end.to raise_exception(RSMP::Secure::ConfigurationError)
      expect do
        RSMP::Secure::Channel.rsmp_context(
          profile: RSMP::Secure::PROFILE,
          initiator_id: '',
          responder_id: 'supervisor'
        )
      end.to raise_exception(RSMP::Secure::ConfigurationError)
    end

    it 'rejects invalid UTF-8 credential identities in the exporter context' do
      expect do
        RSMP::Secure::Channel.rsmp_context(
          profile: RSMP::Secure::PROFILE,
          initiator_id: "\xff".b,
          responder_id: 'supervisor'
        )
      end.to raise_exception(RSMP::Secure::ConfigurationError)
    end

    it 'matches the Secure RSMP v1 HKDF-SHA-256 key schedule vector' do
      exporter_secret = (0...RSMP::Secure::Channel::EXPORTER_SECRET_BYTES).to_a.pack('C*')
      context = RSMP::Secure::Channel.rsmp_context(
        profile: RSMP::Secure::PROFILE,
        initiator_id: 'RN+SI0001',
        responder_id: 'supervisor'
      )
      channel = RSMP::Secure::Channel.new(exporter_secret, role: :initiator, rsmp_context: context)
      traffic_secret = 'fba533cce9ad914357386290334a2f577a9848b91d2545c44c7b46f5fa06ba97'
      i2r_key = '438e9532ddc32f0ed178b4630dbf2997a3acaa57be909117f845e11b3551ff4d'
      r2i_key = '641bb113a1fd043d7aa266d25a75f7dede88221cc5e5b90df119a2ed5d0bca37'

      expect(channel.instance_variable_get(:@traffic_secret).unpack1('H*')).to be == traffic_secret
      expect(channel.session_id.unpack1('H*')).to be == 'a2053e954f583bd8bd340a2e67629ff5'
      expect(channel.instance_variable_get(:@send_key).unpack1('H*')).to be == i2r_key
      expect(channel.instance_variable_get(:@recv_key).unpack1('H*')).to be == r2i_key
      expect(channel.instance_variable_get(:@send_nonce_prefix).unpack1('H*')).to be == '8bb798819d9ec4a8'
      expect(channel.instance_variable_get(:@recv_nonce_prefix).unpack1('H*')).to be == '9df78ed6937d1eab'
    end

    it 'encodes exporter context identities as text even when EDHOC returns binary strings' do
      text_context = RSMP::Secure::Channel.rsmp_context(
        profile: RSMP::Secure::PROFILE,
        initiator_id: 'RN+SI0001',
        responder_id: 'supervisor'
      )
      binary_context = RSMP::Secure::Channel.rsmp_context(
        profile: RSMP::Secure::PROFILE.b,
        initiator_id: 'RN+SI0001'.b,
        responder_id: 'supervisor'.b
      )

      expect(binary_context).to be == text_context
    end

    it 'binds the implemented secure data AAD shape' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      aad = initiator.send(:aad, 'data', 'i2r', 1)

      expect(RSMP::Secure::Cbor.decode(aad)).to be == {
        'connection' => 'single-rsmp-connection',
        'context' => 'rsmp-secure-data-v1',
        'epoch' => 0,
        'idx' => 1,
        'sender' => 'i2r',
        'session' => initiator.session_id,
        'type' => 'data'
      }
    end

    it 'rejects replayed data indices' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: secure_channel_context)
      frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))

      responder.decrypt_frame(frame)

      expect do
        responder.decrypt_frame(frame)
      end.to raise_exception(RSMP::Secure::ReplayError)
    end

    it 'rejects skipped and reordered data indices without advancing replay state' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: secure_channel_context)
      first = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('index' => 1))
      second = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('index' => 2))

      expect do
        responder.decrypt_frame(second)
      end.to raise_exception(
        RSMP::Secure::ReplayError,
        message: be == 'Expected secure frame index 1, got 2'
      )
      expect(RSMP::Secure::Cbor.decode(responder.decrypt_frame(first))).to be == { 'index' => 1 }
      expect(RSMP::Secure::Cbor.decode(responder.decrypt_frame(second))).to be == { 'index' => 2 }
    end

    it 'rejects authentication failures' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: secure_channel_context)
      frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))
      frame['enc'] = frame.fetch('enc').dup
      frame['enc'][2] = frame['enc'].fetch(2).dup.tap do |ciphertext|
        ciphertext.setbyte(ciphertext.bytesize - 1, ciphertext.getbyte(ciphertext.bytesize - 1) ^ 0x01)
      end

      expect do
        responder.decrypt_frame(frame)
      end.to raise_exception(RSMP::Secure::AuthenticationError)
    end

    it 'rejects missing, unknown, and mistyped protected-frame fields' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('index' => 1))
      invalid_frames = [
        frame.except('epoch'),
        frame.merge('unknown' => true),
        frame.merge('epoch' => '0')
      ]

      invalid_frames.each do |invalid_frame|
        responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: secure_channel_context)
        expect do
          responder.decrypt_frame(invalid_frame)
        end.to raise_exception(RSMP::Secure::FrameError)
      end
    end

    it 'rejects COSE_Encrypt0 with the wrong algorithm or a non-minimal Partial IV' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: secure_channel_context)
      frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))
      wrong_algorithm = frame.merge('enc' => frame.fetch('enc').dup)
      wrong_algorithm['enc'][0] = RSMP::Secure::Cbor.encode(1 => 10)
      non_minimal_index = frame.merge('enc' => frame.fetch('enc').dup)
      non_minimal_index['enc'][1] = { 6 => "\x00\x01".b }

      expect do
        responder.decrypt_frame(wrong_algorithm)
      end.to raise_exception(RSMP::Secure::FrameError)
      expect do
        responder.decrypt_frame(non_minimal_index)
      end.to raise_exception(RSMP::Secure::FrameError)
    end

    it 'encrypts rekey control frames with distinct frame type authentication' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator, rsmp_context: secure_channel_context)
      responder = RSMP::Secure::Channel.new(secret, role: :responder, rsmp_context: secure_channel_context)

      frame = initiator.encrypt_control('kind' => 'rekey_msg1', 'next_epoch' => 1, 'edhoc' => 'msg1'.b)

      expect(responder.decrypt_control_frame(frame)).to be == {
        'edhoc' => 'msg1'.b,
        'kind' => 'rekey_msg1',
        'next_epoch' => 1
      }

      data_like = frame.merge('type' => 'data')
      expect do
        RSMP::Secure::Channel.new(secret, role: :responder,
                                          rsmp_context: secure_channel_context).decrypt_frame(data_like)
      end.to raise_exception(RSMP::Secure::AuthenticationError)
    end
  end

  with RSMP::Secure::Protocol do
    it 'binds a reject-all EAD handler and fresh four-byte EDHOC connection identifiers' do
      Dir.mktmpdir do |dir|
        site_settings, = secure_settings(dir)
        protocol = RSMP::Secure::Protocol.new(SecureMemoryStream.new, role: :initiator, settings: site_settings)
        first = protocol.send(:build_edhoc_session)
        second = protocol.send(:build_edhoc_session)
        ead = RSMP::Secure::RejectEad.new

        expect(first.connection_id.bytesize).to be == 4
        expect(first.connection_id).not.to be == second.connection_id
        expect(first.instance_variable_get(:@ead)).not.to be_nil
        expect(ead.supports?(1)).to be == false
        expect do
          ead.process(nil, [Edhoc::EAD::Token.new(label: 1, value: 'x')])
        end.to raise_exception(Edhoc::EadError)
      ensure
        first&.close
        second&.close
        protocol&.close
      end
    end

    it 'rejects duplicate provisioned KIDs even when credential subjects differ' do
      Dir.mktmpdir do |dir|
        vector = Edhoc::TestVector.suite0
        local = secure_identity(dir, 'site', vector.fetch(:initiator_private_key),
                                vector_secure_credential(vector, :initiator, 'RN+SI0001'))
        shared_public_key = vector.fetch(:responder_public_key)
        settings = local.merge(
          'peers' => [
            {
              'id' => 'supervisor-a',
              'credential' => write_secure_file(
                dir, 'supervisor-a.cred',
                secure_credential('supervisor-a', public_key: shared_public_key)
              )
            },
            {
              'id' => 'supervisor-b',
              'credential' => write_secure_file(
                dir, 'supervisor-b.cred',
                secure_credential('supervisor-b', public_key: shared_public_key)
              )
            }
          ]
        )

        expect do
          RSMP::Secure::Protocol.new(SecureMemoryStream.new, role: :initiator, settings: settings)
        end.to raise_exception(
          RSMP::Secure::ConfigurationError,
          message: be(:include?, 'duplicate secure peer credential KID')
        )
      end
    end

    it 'sends at most one fixed non-sensitive RFC 9528 error after a valid wrapper' do
      Dir.mktmpdir do |dir|
        _site_settings, supervisor_settings = secure_settings(dir)
        stream = SecureMemoryStream.new
        protocol = RSMP::Secure::Protocol.new(stream, role: :responder, settings: supervisor_settings)
        protocol.instance_variable_set(:@received_valid_handshake_wrapper, true)

        2.times { protocol.send(:send_edhoc_error) }
        frame = RSMP::Secure::FrameIO.new(SecureMemoryStream.new(stream.written), max_frame_size: 65_536).read
        error = Edhoc::ErrorMessage.parse(frame.fetch('edhoc'))

        expect(frame.except('edhoc')).to be == {
          'v' => 1,
          'type' => 'edhoc_error',
          'profile' => RSMP::Secure::PROFILE
        }
        expect(error.code).to be == :unspecified
        expect(error.text).to be == 'EDHOC handshake failed'
        expect(protocol.traffic_stats.written_frames).to be == 1
      ensure
        protocol&.close
      end
    end

    it 'passes the exact RSMP context to the EDHOC exporter' do
      calls = []
      session = Object.new
      session.define_singleton_method(:export) do |label:, context:, length:|
        calls << [label, context, length]
        's'.b * length
      end
      protocol = RSMP::Secure::Protocol.allocate
      protocol.instance_variable_set(:@role, :initiator)
      protocol.instance_variable_set(:@settings, 'profile' => RSMP::Secure::PROFILE)
      protocol.instance_variable_set(:@local_id, 'RN+SI0001')
      protocol.instance_variable_set(:@authenticated_peer_id, 'supervisor')

      channel = protocol.send(:build_channel, session, epoch: 0)

      expect(calls).to be == [[RSMP::Secure::Channel::EXPORTER_LABEL,
                               secure_channel_context,
                               RSMP::Secure::Channel::EXPORTER_SECRET_BYTES]]
      expect(RSMP::Secure::Channel::EXPORTER_LABEL).to be == 32_768
      expect(channel.rsmp_context).to be == secure_channel_context
    end

    it 'rejects direct top-level public peer credentials without a resolved peer list' do
      Dir.mktmpdir do |dir|
        vector = Edhoc::TestVector.suite0
        settings = {
          'private_key' => write_secure_file(dir, 'site-private.key', vector.fetch(:initiator_private_key)),
          'credential' => write_secure_file(dir, 'site.cred',
                                            vector_secure_credential(vector, :initiator, 'RN+SI0001'))
        }

        expect do
          RSMP::Secure::Protocol.new(SecureMemoryStream.new, role: :initiator, settings: settings)
        end.to raise_exception(RSMP::Secure::ConfigurationError)
      end
    end

    it 'reports when EDHOC rejects an unknown credential' do
      Dir.mktmpdir do |dir|
        vector = Edhoc::TestVector.suite0
        unknown_site = generated_secure_identity('RN+SI0002')
        site_settings = {
          'private_key' => write_secure_file(dir, 'site-private.key', unknown_site.fetch(:private_key)),
          'credential' => write_secure_file(dir, 'unknown-site.cred', unknown_site.fetch(:credential)),
          'peers' => [{
            'id' => 'supervisor',
            'credential' => write_secure_file(dir, 'supervisor.cred',
                                              vector_secure_credential(vector, :responder, 'supervisor'))
          }],
          'handshake_timeout' => 2
        }
        supervisor_settings = {
          'private_key' => write_secure_file(dir, 'supervisor-private.key', vector.fetch(:responder_private_key)),
          'credential' => write_secure_file(dir, 'supervisor.cred',
                                            vector_secure_credential(vector, :responder, 'supervisor')),
          'peers' => [{
            'id' => 'RN+SI0001',
            'credential' => write_secure_file(dir, 'site.cred',
                                              vector_secure_credential(vector, :initiator, 'RN+SI0001'))
          }],
          'handshake_timeout' => 2
        }
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)

        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator, settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings
          )
        end

        expect do
          responder_task.wait
        end.to raise_exception(
          RSMP::HandshakeError,
          message: be(:include?, 'EDHOC handshake failed: peer credential is not trusted')
        )
      ensure
        initiator_task&.stop
        responder_task&.stop
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'rejects a credential revoked before a new secure handshake' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        revocations = RSMP::Secure::RevocationList.new
        revocations.revoke('RN+SI0001')
        supervisor_settings = RSMP::Secure.with_runtime_policy(
          supervisor_settings,
          revocation_list: revocations
        )
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        responder_logs = []
        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator,
                                                                         settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(supervisor_io), role: :responder,
                                                                               settings: supervisor_settings,
                                                                               log: lambda { |message, options = {}|
                                                                                 responder_logs << [message, options]
                                                                               })
        end
        expect do
          responder_task.wait
        end.to raise_exception(
          RSMP::Secure::AuthenticationError,
          message: be == 'Authenticated secure credential has been revoked'
        )
        expect(responder_logs).to be == [
          ['Secure handshake failed (category: authentication)', { level: :warning }]
        ]
        site = initiator_task.wait
      ensure
        initiator_task&.stop
        responder_task&.stop
        site&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'reports legacy JSON sent to a secure responder as a handshake error' do
      Dir.mktmpdir do |dir|
        vector = Edhoc::TestVector.suite0
        settings = supervisor_secure_settings(dir, vector)
        legacy_packet = %({"mType":"rSMsg","type":"Version"}\f)
        stream = SecureMemoryStream.new(legacy_packet)
        protocol = RSMP::Secure::Protocol.new(
          stream,
          role: :responder,
          settings: settings
        )

        expect do
          protocol.handshake!
        end.to raise_exception(
          RSMP::HandshakeError,
          message: be(:include?, 'Secure RSMP handshake failed')
        )
        expect(stream.written).to be(:empty?)
      end
    end

    it 'rejects application data until the initiator authenticates mandatory EDHOC message 4' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        initiator = RSMP::Secure::Protocol.new(
          IO::Stream::Buffered.new(site_io), role: :initiator, settings: site_settings
        )
        responder = RSMP::Secure::Protocol.new(
          IO::Stream::Buffered.new(supervisor_io), role: :responder, settings: supervisor_settings
        )
        original_write_edhoc = responder.method(:write_edhoc)
        responder.define_singleton_method(:write_edhoc) do |number, message|
          if number == 4
            write_frame('v' => 1, 'type' => 'data', 'epoch' => 0, 'enc' => [])
          else
            original_write_edhoc.call(number, message)
          end
        end

        initiator_task = Async::Task.current.async { initiator.handshake! }
        responder_task = Async::Task.current.async { responder.handshake! }

        expect do
          initiator_task.wait
        end.to raise_exception(
          RSMP::HandshakeError,
          message: be(:include?, 'Secure handshake frame contains unexpected fields')
        )
      ensure
        initiator_task&.stop
        responder_task&.stop
        initiator&.close
        responder&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'runs EDHOC and exchanges encrypted RSMP messages' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site_logs = []
        supervisor_logs = []
        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(site_io),
            role: :initiator,
            settings: site_settings,
            log: ->(message, options = {}) { site_logs << [message, options] }
          )
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings,
            log: ->(message, options = {}) { supervisor_logs << [message, options] }
          )
        end
        site = initiator_task.wait
        supervisor = responder_task.wait

        expect(site_logs).to be == [['Secure handshake with peer supervisor complete (initiator, epoch 0)', { level: :info }]]
        expect(supervisor_logs).to be == [['Secure handshake with peer RN+SI0001 complete (responder, epoch 0)', { level: :info }]]
        expect(site.traffic_stats.written_frames).to be == 2
        expect(supervisor.traffic_stats.written_frames).to be == 2

        version = {
          'mType' => 'rSMsg',
          'type' => 'Version',
          'step' => 'Request',
          'RSMP' => [{ 'vers' => '3.3.0' }],
          'siteId' => [{ 'sId' => 'RN+SI0001' }],
          'mId' => '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6'
        }
        site.write_lines(JSON.generate(version))

        expect(JSON.parse(supervisor.read_line)).to be == version
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'seals one immutable credential, RSMP role, identity, and Core authorization context' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator,
                                                                         settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(supervisor_io), role: :responder,
                                                                               settings: supervisor_settings)
        end
        site = initiator_task.wait
        supervisor = responder_task.wait

        expect(supervisor.authorize!(rsmp_id: 'RN+SI0001', core_version: '3.3.0')).to be == true
        context = supervisor.authorization_context
        expect(context.to_h).to be == {
          credential_id: 'RN+SI0001',
          rsmp_id: 'RN+SI0001',
          role: :peer,
          core_version: '3.3.0'
        }
        expect(context).to be(:frozen?)
        expect(supervisor.authorize!(rsmp_id: 'RN+SI0001', core_version: '3.3.0')).to be == true
        expect do
          supervisor.authorize!(rsmp_id: 'RN+SI9999', core_version: '3.3.0')
        end.to raise_exception(RSMP::Secure::AuthenticationError)
        expect(supervisor.channel).to be_nil
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'closes when application data arrives before Version authorization' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator,
                                                                         settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(supervisor_io), role: :responder,
                                                                               settings: supervisor_settings)
        end
        site = initiator_task.wait
        supervisor = responder_task.wait
        frame = site.channel.encrypt_payload(
          RSMP::Secure::Cbor.encode('mType' => 'rSMsg', 'type' => 'Watchdog')
        )
        site.write_frame(frame)

        expect do
          supervisor.read_line
        end.to raise_exception(
          RSMP::Secure::AuthenticationError,
          message: be(:include?, 'not permitted before secure authorization')
        )
        expect(supervisor.channel).to be_nil
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'closes locally instead of sending application data before Version authorization' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator,
                                                                         settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(supervisor_io), role: :responder,
                                                                               settings: supervisor_settings)
        end
        site = initiator_task.wait
        supervisor = responder_task.wait

        expect do
          site.write_lines(JSON.generate('mType' => 'rSMsg', 'type' => 'Watchdog'))
        end.to raise_exception(
          RSMP::Secure::AuthenticationError,
          message: be(:include?, 'not permitted before secure authorization')
        )
        expect(site.channel).to be_nil
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'binds pre-authorization acknowledgements to the outbound Version message' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator,
                                                                         settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(supervisor_io), role: :responder,
                                                                               settings: supervisor_settings)
        end
        site = initiator_task.wait
        supervisor = responder_task.wait
        version = {
          'mType' => 'rSMsg',
          'type' => 'Version',
          'step' => 'Request',
          'RSMP' => [{ 'vers' => '3.3.0' }],
          'siteId' => [{ 'sId' => 'RN+SI0001' }],
          'mId' => '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6'
        }
        site.write_lines(JSON.generate(version))
        expect(JSON.parse(supervisor.read_line)).to be == version

        forged_ack = supervisor.channel.encrypt_payload(
          RSMP::Secure::Cbor.encode(
            'mType' => 'rSMsg',
            'type' => 'MessageAck',
            'oMId' => 'not-the-version-message-id'
          )
        )
        supervisor.write_frame(forged_ack)

        expect do
          site.read_line
        end.to raise_exception(
          RSMP::Secure::AuthenticationError,
          message: be(:include?, 'does not acknowledge the protected Version exchange')
        )
        expect(site.channel).to be_nil
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'closes instead of sending a second Version message' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator,
                                                                         settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(supervisor_io), role: :responder,
                                                                               settings: supervisor_settings)
        end
        site = initiator_task.wait
        supervisor = responder_task.wait
        first = {
          'mType' => 'rSMsg',
          'type' => 'Version',
          'step' => 'Request',
          'RSMP' => [{ 'vers' => '3.3.0' }],
          'siteId' => [{ 'sId' => 'RN+SI0001' }],
          'mId' => '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6'
        }
        site.write_lines(JSON.generate(first))
        expect(JSON.parse(supervisor.read_line)).to be == first

        expect do
          site.write_lines(JSON.generate(first.merge('mId' => '17f0115d-e221-441f-8c94-a7e706b58e76')))
        end.to raise_exception(
          RSMP::Secure::AuthenticationError,
          message: be(:include?, 'second outbound RSMP Version')
        )
        expect(site.channel).to be_nil
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'closes when a peer sends a second Version message' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator,
                                                                         settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(supervisor_io), role: :responder,
                                                                               settings: supervisor_settings)
        end
        site = initiator_task.wait
        supervisor = responder_task.wait
        first = {
          'mType' => 'rSMsg',
          'type' => 'Version',
          'step' => 'Request',
          'RSMP' => [{ 'vers' => '3.3.0' }],
          'siteId' => [{ 'sId' => 'RN+SI0001' }],
          'mId' => '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6'
        }
        site.write_lines(JSON.generate(first))
        expect(JSON.parse(supervisor.read_line)).to be == first

        second = first.merge('mId' => '17f0115d-e221-441f-8c94-a7e706b58e76')
        site.write_frame(site.channel.encrypt_payload(RSMP::Secure::Cbor.encode(second)))

        expect do
          supervisor.read_line
        end.to raise_exception(
          RSMP::Secure::AuthenticationError,
          message: be(:include?, 'second inbound RSMP Version')
        )
        expect(supervisor.channel).to be_nil
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'runs the v1 profile with pinned CCS credentials and exchanges encrypted RSMP messages' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        initiator_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator, settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          RSMP::Secure.build_protocol(IO::Stream::Buffered.new(supervisor_io), role: :responder, settings: supervisor_settings)
        end
        site = initiator_task.wait
        supervisor = responder_task.wait
        authorize_secure_pair(site, supervisor)

        watchdog = {
          'mType' => 'rSMsg',
          'type' => 'Watchdog',
          'wTs' => '2026-07-08T08:10:00.000Z',
          'mId' => '69d0035d-00da-4407-b47a-f9fd540b5e83'
        }
        site.write_lines(JSON.generate(watchdog))

        expect(JSON.parse(supervisor.read_line)).to be == watchdog
        expect(site.channel.profile).to be == RSMP::Secure::V1_PROFILE
        expect(supervisor.channel.profile).to be == RSMP::Secure::V1_PROFILE
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'renews traffic keys using encrypted EDHOC rekey control frames' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site = nil
        supervisor = nil
        site_logs = []
        supervisor_logs = []

        initiator_task = Async::Task.current.async do
          site = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(site_io),
            role: :initiator,
            settings: site_settings,
            log: ->(message, options = {}) { site_logs << [message, options] }
          )
        end
        responder_task = Async::Task.current.async do
          supervisor = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings,
            log: ->(message, options = {}) { supervisor_logs << [message, options] }
          )
        end
        initiator_task.wait
        responder_task.wait
        authorize_secure_pair(site, supervisor)

        pre_rekey = {
          'mType' => 'rSMsg',
          'type' => 'Watchdog',
          'mId' => '36f85650-ee72-42b1-a097-0f4f48183ef5',
          'wTs' => '2026-07-07T13:15:00.000Z'
        }
        site.write_lines(JSON.generate(pre_rekey))
        expect(JSON.parse(supervisor.read_line)).to be == pre_rekey

        secret_names = %i[@traffic_secret @send_key @recv_key @send_nonce_prefix @recv_nonce_prefix]
        old_site_channel = site.channel
        old_supervisor_channel = supervisor.channel
        old_site_secret_refs = secret_names.map { |name| old_site_channel.instance_variable_get(name) }
        old_supervisor_secret_refs = secret_names.map { |name| old_supervisor_channel.instance_variable_get(name) }
        old_site_secret_values = old_site_secret_refs.map(&:dup)
        old_supervisor_secret_values = old_supervisor_secret_refs.map(&:dup)
        session_id = site.channel.session_id
        expect(supervisor.channel.session_id).to be == session_id

        expect(site.rekey!).to be == true
        expect(site.channel.epoch).to be == 1
        expect(supervisor.channel.epoch).to be == 1
        expect(site.channel.session_id).to be == session_id
        expect(supervisor.channel.session_id).to be == session_id
        expect(site.channel.instance_variable_get(:@recv_idx)).to be == 1
        expect(supervisor.channel.instance_variable_get(:@send_idx)).to be == 1
        expect(old_site_secret_refs.all?(&:empty?)).to be == true
        expect(old_supervisor_secret_refs.all?(&:empty?)).to be == true
        expect(secret_names.map { |name| old_site_channel.instance_variable_get(name) }.all?(&:nil?)).to be == true
        expect(secret_names.map { |name| old_supervisor_channel.instance_variable_get(name) }.all?(&:nil?)).to be == true
        expect(secret_names.map { |name| site.channel.instance_variable_get(name) }).not.to be == old_site_secret_values
        expect(secret_names.map { |name| supervisor.channel.instance_variable_get(name) }).not.to be == old_supervisor_secret_values

        post_rekey = pre_rekey.merge(
          'mId' => 'c6a0ec38-45a7-4339-a51c-4499deff1682',
          'wTs' => '2026-07-07T13:16:00.000Z'
        )
        site.write_lines(JSON.generate(post_rekey))
        expect(JSON.parse(supervisor.read_line)).to be == post_rekey
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'waits for the responder acknowledgement before installing the new channel' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site = nil
        supervisor = nil
        rekey_task = nil
        acknowledgement_release = Async::Queue.new
        acknowledgement_released = false

        initiator_task = Async::Task.current.async do
          site = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(site_io),
            role: :initiator,
            settings: site_settings
          )
        end
        responder_task = Async::Task.current.async do
          supervisor = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings
          )
        end
        initiator_task.wait
        responder_task.wait
        authorize_secure_pair(site, supervisor)

        acknowledgement_attempted = Async::Queue.new
        frame_io = supervisor.instance_variable_get(:@frame_io)
        original_write = frame_io.method(:write)
        frame_io.define_singleton_method(:write) do |frame|
          if frame['type'] == 'rekey' && frame['epoch'] == 1
            acknowledgement_attempted.enqueue(true)
            acknowledgement_release.dequeue
          end
          original_write.call(frame)
        end

        rekey_task = Async::Task.current.async { site.rekey! }
        acknowledgement_attempted.dequeue

        expect(rekey_task).not.to be(:complete?)
        expect(site.channel.epoch).to be == 0
        expect(supervisor.channel.epoch).to be == 1

        acknowledgement_release.enqueue(true)
        acknowledgement_released = true
        expect(rekey_task.wait).to be == true
        expect(site.channel.epoch).to be == 1
      ensure
        acknowledgement_release&.enqueue(true) unless acknowledgement_released
        rekey_task&.stop
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'buffers in-flight data frames while waiting for rekey control responses' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site = nil
        supervisor = nil

        initiator_task = Async::Task.current.async do
          site = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(site_io),
            role: :initiator,
            settings: site_settings
          )
        end
        responder_task = Async::Task.current.async do
          supervisor = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings
          )
        end
        initiator_task.wait
        responder_task.wait
        authorize_secure_pair(site, supervisor)

        in_flight = {
          'mType' => 'rSMsg',
          'type' => 'Watchdog',
          'mId' => '2887b7d0-b8ab-40d1-8cd7-035731603381',
          'wTs' => '2026-07-07T13:49:12.436Z'
        }
        supervisor.write_lines(JSON.generate(in_flight))

        expect(site.rekey!).to be == true

        expect(site.channel.epoch).to be == 1
        expect(supervisor.channel.epoch).to be == 1
        expect(JSON.parse(site.read_line)).to be == in_flight
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'routes initiator rekey responses through an already active reader' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site = nil
        supervisor = nil

        initiator_task = Async::Task.current.async do
          site = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(site_io),
            role: :initiator,
            settings: site_settings
          )
        end
        responder_task = Async::Task.current.async do
          supervisor = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings
          )
        end
        initiator_task.wait
        responder_task.wait
        authorize_secure_pair(site, supervisor)

        site_reader = Async::Task.current.async { site.read_line }
        expect(site.rekey!).to be == true

        response = {
          'mType' => 'rSMsg',
          'type' => 'Watchdog',
          'mId' => '4c2eaf90-a184-4c30-a51f-18697bca5a90',
          'wTs' => '2026-07-07T14:10:00.000Z'
        }
        supervisor.write_lines(JSON.generate(response))

        expect(JSON.parse(site_reader.wait)).to be == response
        expect(site.channel.epoch).to be == 1
        expect(supervisor.channel.epoch).to be == 1
      ensure
        site_reader&.stop
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'lets the responder request rekey while only the original initiator starts EDHOC' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site = nil
        supervisor = nil

        initiator_task = Async::Task.current.async do
          site = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(site_io),
            role: :initiator,
            settings: site_settings
          )
        end
        responder_task = Async::Task.current.async do
          supervisor = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings
          )
        end
        initiator_task.wait
        responder_task.wait
        authorize_secure_pair(site, supervisor)

        expect(supervisor.rekey!).to be == true
        expect(site.channel.epoch).to be == 1
        expect(supervisor.channel.epoch).to be == 1
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'fails the transport and wakes callers on authentication failure' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site = nil
        supervisor = nil

        initiator_task = Async::Task.current.async do
          site = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(site_io),
            role: :initiator,
            settings: site_settings
          )
        end
        responder_task = Async::Task.current.async do
          supervisor = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings
          )
        end
        initiator_task.wait
        responder_task.wait
        authorize_secure_pair(site, supervisor)

        reader = Async::Task.current.async { site.read_line }
        frame = supervisor.channel.encrypt_payload(
          RSMP::Secure::Cbor.encode(
            'mType' => 'rSMsg',
            'type' => 'Watchdog',
            'mId' => '0dc5734c-17e6-4939-acb4-b3be538c9911',
            'wTs' => '2026-07-07T14:25:00.000Z'
          )
        )
        frame['enc'] = frame.fetch('enc').dup
        frame['enc'][2] = frame['enc'].fetch(2).dup.tap do |ciphertext|
          ciphertext.setbyte(ciphertext.bytesize - 1, ciphertext.getbyte(ciphertext.bytesize - 1) ^ 0x01)
        end
        supervisor.write_frame(frame)

        read_error = nil
        begin
          reader.wait
        rescue RSMP::Secure::AuthenticationError => e
          read_error = e
        end

        expect(read_error).to be_a(RSMP::Secure::AuthenticationError)
        expect(read_error.message).to be == 'Secure RSMP authentication failed'

        expect do
          site.write_lines(JSON.generate('mType' => 'rSMsg', 'type' => 'Watchdog'))
        end.to raise_exception(
          RSMP::HandshakeError,
          message: be == 'Secure RSMP handshake is not complete'
        )
      ensure
        reader&.stop
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'automatically rekeys after the configured message count' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_settings = site_settings.merge(
          'rekey_after_messages' => 4
        )
        supervisor_settings = supervisor_settings.merge(
          'rekey_after_messages' => 4
        )
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site = nil
        supervisor = nil
        site_logs = []
        supervisor_logs = []

        initiator_task = Async::Task.current.async do
          site = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(site_io),
            role: :initiator,
            settings: site_settings,
            log: ->(message, options = {}) { site_logs << [message, options] }
          )
        end
        responder_task = Async::Task.current.async do
          supervisor = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings,
            log: ->(message, options = {}) { supervisor_logs << [message, options] }
          )
        end
        initiator_task.wait
        responder_task.wait
        authorize_secure_pair(site, supervisor)
        rekey_requests = 0
        original_encrypt_control = supervisor.channel.method(:encrypt_control)
        supervisor.channel.define_singleton_method(:encrypt_control) do |attributes|
          rekey_requests += 1 if attributes['kind'] == 'rekey_request'
          original_encrypt_control.call(attributes)
        end

        first = {
          'mType' => 'rSMsg',
          'type' => 'Watchdog',
          'mId' => '0ef59517-9a06-4863-9f80-4f9003615ea3',
          'wTs' => '2026-07-07T13:20:00.000Z'
        }
        second = first.merge(
          'mId' => 'fb6241d7-37f8-412f-889e-2fa15bddb7b5',
          'wTs' => '2026-07-07T13:21:00.000Z'
        )

        site.write_lines(JSON.generate(first))
        expect(JSON.parse(supervisor.read_line)).to be == first

        writer = Async::Task.current.async { site.write_lines(JSON.generate(second)) }
        expect(JSON.parse(supervisor.read_line)).to be == second
        writer.wait

        expect(site.channel.epoch).to be == 1
        expect(supervisor.channel.epoch).to be == 1
        expect(rekey_requests).to be == 1
        expect(site_logs).to be == [
          ['Secure handshake with peer supervisor complete (initiator, epoch 0)', { level: :info }],
          ['Secure authorization complete for supervisor as peer, Core 3.3.0', { level: :info }],
          ['Secure rekey with peer supervisor started (initiator, epoch 1)', { level: :info }],
          ['Secure rekey with peer supervisor complete (initiator, epoch 1)', { level: :info }]
        ]
        expect(supervisor_logs).to be == [
          ['Secure handshake with peer RN+SI0001 complete (responder, epoch 0)', { level: :info }],
          ['Secure authorization complete for RN+SI0001 as peer, Core 3.3.0', { level: :info }],
          ['Secure rekey with peer RN+SI0001 started (responder, epoch 1)', { level: :info }],
          ['Secure rekey with peer RN+SI0001 complete (responder, epoch 1)', { level: :info }]
        ]
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'automatically rekeys before the mandatory ciphertext-byte limit' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_settings = site_settings.merge('rekey_after_bytes' => 150_000)
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site = nil
        supervisor = nil
        initiator_task = Async::Task.current.async do
          site = RSMP::Secure.build_protocol(IO::Stream::Buffered.new(site_io), role: :initiator,
                                                                                settings: site_settings)
        end
        responder_task = Async::Task.current.async do
          supervisor = RSMP::Secure.build_protocol(IO::Stream::Buffered.new(supervisor_io), role: :responder,
                                                                                            settings: supervisor_settings)
        end
        initiator_task.wait
        responder_task.wait
        authorize_secure_pair(site, supervisor)
        message = {
          'mType' => 'rSMsg',
          'type' => 'Watchdog',
          'blob' => 'x' * 20_000
        }

        site.write_lines(JSON.generate(message))

        expect(JSON.parse(supervisor.read_line)).to be == message
        expect(site.channel.epoch).to be == 1
        expect(supervisor.channel.epoch).to be == 1
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'serializes concurrent writes so only one automatic rekey starts for an epoch' do
      Dir.mktmpdir do |dir|
        site_settings, supervisor_settings = secure_settings(dir)
        site_settings = site_settings.merge(
          'rekey_after_messages' => 4
        )
        site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
        site = nil
        supervisor = nil
        site_logs = []

        initiator_task = Async::Task.current.async do
          site = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(site_io),
            role: :initiator,
            settings: site_settings,
            log: ->(message, options = {}) { site_logs << [message, options] }
          )
        end
        responder_task = Async::Task.current.async do
          supervisor = RSMP::Secure.build_protocol(
            IO::Stream::Buffered.new(supervisor_io),
            role: :responder,
            settings: supervisor_settings
          )
        end
        initiator_task.wait
        responder_task.wait
        authorize_secure_pair(site, supervisor)

        first = {
          'mType' => 'rSMsg',
          'type' => 'Watchdog',
          'mId' => 'bcae0a9b-67e4-4f1b-b076-8647d0b80f9d',
          'wTs' => '2026-07-07T13:24:00.000Z'
        }
        second = first.merge(
          'mId' => 'c773a249-049b-4cb8-b613-d234b26747db',
          'wTs' => '2026-07-07T13:25:00.000Z'
        )
        third = first.merge(
          'mId' => 'd4f7494d-6ff8-4e4f-8607-4da1a9e04d27',
          'wTs' => '2026-07-07T13:26:00.000Z'
        )

        site.write_lines(JSON.generate(first))
        expect(JSON.parse(supervisor.read_line)).to be == first

        second_writer = Async::Task.current.async { site.write_lines(JSON.generate(second)) }
        third_writer = Async::Task.current.async { site.write_lines(JSON.generate(third)) }
        received = [JSON.parse(supervisor.read_line), JSON.parse(supervisor.read_line)]
        second_writer.wait
        third_writer.wait

        expect(received.map { |message| message.fetch('mId') }.sort).to be == [second['mId'], third['mId']].sort
        expect(site.channel.epoch).to be == 1
        expect(supervisor.channel.epoch).to be == 1
        expect(site_logs.count { |entry| entry.first.include?('rekey') && entry.first.include?('started') }).to be == 1
        expect(site_logs).to be(:include?, ['Secure rekey with peer supervisor started (initiator, epoch 1)', { level: :info }])
      ensure
        site&.close
        supervisor&.close
        site_io&.close
        supervisor_io&.close
      end
    end

    it 'automatically rekeys after the configured key lifetime before the next write' do
      with_mocked_process_clock do
        Dir.mktmpdir do |dir|
          site_settings, supervisor_settings = secure_settings(dir)
          site_settings = site_settings.merge(
            'rekey_after_seconds' => 10
          )
          site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
          site = nil
          supervisor = nil

          initiator_task = Async::Task.current.async do
            site = RSMP::Secure.build_protocol(
              IO::Stream::Buffered.new(site_io),
              role: :initiator,
              settings: site_settings
            )
          end
          responder_task = Async::Task.current.async do
            supervisor = RSMP::Secure.build_protocol(
              IO::Stream::Buffered.new(supervisor_io),
              role: :responder,
              settings: supervisor_settings
            )
          end
          initiator_task.wait
          responder_task.wait
          authorize_secure_pair(site, supervisor)

          first = {
            'mType' => 'rSMsg',
            'type' => 'Watchdog',
            'mId' => 'a11d40d5-cb90-4c3e-8094-991df0ea6c22',
            'wTs' => '2026-07-07T13:22:00.000Z'
          }
          second = first.merge(
            'mId' => '4eb9d4f5-ecad-49df-bf23-7935c66bd6fa',
            'wTs' => '2026-07-07T13:23:00.000Z'
          )

          site.write_lines(JSON.generate(first))
          expect(JSON.parse(supervisor.read_line)).to be == first

          Timecop.travel(11) do
            writer = Async::Task.current.async { site.write_lines(JSON.generate(second)) }
            expect(JSON.parse(supervisor.read_line)).to be == second
            writer.wait
          end

          expect(site.channel.epoch).to be == 1
          expect(supervisor.channel.epoch).to be == 1
        ensure
          site&.close
          supervisor&.close
          site_io&.close
          supervisor_io&.close
        end
      end
    end

    it 'performs one automatic rekey when message count and key lifetime are both due' do
      with_mocked_process_clock do
        Dir.mktmpdir do |dir|
          site_settings, supervisor_settings = secure_settings(dir)
          site_settings = site_settings.merge(
            'rekey_after_messages' => 4,
            'rekey_after_seconds' => 10
          )
          site_io, supervisor_io = Socket.pair(:UNIX, :STREAM, 0)
          site = nil
          supervisor = nil
          site_logs = []

          initiator_task = Async::Task.current.async do
            site = RSMP::Secure.build_protocol(
              IO::Stream::Buffered.new(site_io),
              role: :initiator,
              settings: site_settings,
              log: ->(message, options = {}) { site_logs << [message, options] }
            )
          end
          responder_task = Async::Task.current.async do
            supervisor = RSMP::Secure.build_protocol(
              IO::Stream::Buffered.new(supervisor_io),
              role: :responder,
              settings: supervisor_settings
            )
          end
          initiator_task.wait
          responder_task.wait
          authorize_secure_pair(site, supervisor)

          first = {
            'mType' => 'rSMsg',
            'type' => 'Watchdog',
            'mId' => '1e7445aa-083a-4e7f-981b-3680a3780fe8',
            'wTs' => '2026-07-07T14:40:00.000Z'
          }
          second = first.merge(
            'mId' => 'a4d4708d-7084-4a50-8887-7e0cf7707d75',
            'wTs' => '2026-07-07T14:41:00.000Z'
          )

          site.write_lines(JSON.generate(first))
          expect(JSON.parse(supervisor.read_line)).to be == first

          Timecop.travel(11) do
            writer = Async::Task.current.async { site.write_lines(JSON.generate(second)) }
            expect(JSON.parse(supervisor.read_line)).to be == second
            writer.wait
          end

          expect(site.channel.epoch).to be == 1
          expect(supervisor.channel.epoch).to be == 1
          expect(site_logs.count { |entry| entry.first.include?('rekey') && entry.first.include?('started') }).to be == 1
          expect(site_logs).to be(:include?, ['Secure rekey with peer supervisor started (initiator, epoch 1)', { level: :info }])
        ensure
          site&.close
          supervisor&.close
          site_io&.close
          supervisor_io&.close
        end
      end
    end

    it 'rejects application data while a required rekey is in progress' do
      old_secret = 'o' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      new_secret = 'n' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      old_channel = RSMP::Secure::Channel.new(old_secret, role: :responder,
                                                          rsmp_context: secure_channel_context)
      peer_channel = RSMP::Secure::Channel.new(new_secret, role: :initiator, epoch: 1,
                                                           session_id: old_channel.session_id,
                                                           rsmp_context: secure_channel_context)
      transport = RSMP::Secure::Transport.new(
        RSMP::Secure::Transport::Config.new(
          frame_io: nil,
          role: :responder,
          settings: RSMP::Secure.settings({}),
          channel: old_channel,
          session_builder: nil,
          channel_builder: nil,
          log: nil,
          parent: Async::Task.current
        )
      )
      message = {
        'mType' => 'rSMsg',
        'type' => 'Watchdog',
        'mId' => '4c6155c5-f1a1-45dc-a63f-604e08d4330f',
        'wTs' => '2026-07-07T14:35:00.000Z'
      }
      frame = peer_channel.encrypt_payload(RSMP::Secure::Cbor.encode(message))

      transport.instance_variable_set(:@rekeying, true)
      expect do
        transport.send(:enqueue_plaintext, frame)
      end.to raise_exception(
        RSMP::Secure::FrameError,
        message: be == 'Application data is not permitted while secure rekey is required or in progress'
      )
    ensure
      transport&.close
    end

    it 'rejects a rekey request delivered to the responder role' do
      secret = 'o' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      channel = RSMP::Secure::Channel.new(secret, role: :responder,
                                                  rsmp_context: secure_channel_context)
      peer_channel = RSMP::Secure::Channel.new(secret, role: :initiator,
                                                       rsmp_context: secure_channel_context)
      transport = RSMP::Secure::Transport.new(
        RSMP::Secure::Transport::Config.new(
          frame_io: nil,
          role: :responder,
          settings: RSMP::Secure.settings({}),
          channel: channel,
          session_builder: nil,
          channel_builder: nil,
          log: nil,
          parent: Async::Task.current
        )
      )
      frame = peer_channel.encrypt_control('kind' => 'rekey_request', 'next_epoch' => 1)

      expect do
        transport.send(:process_rekey_frame, frame)
      end.to raise_exception(
        RSMP::Secure::FrameError,
        message: be == 'Secure responder received a responder-only rekey request'
      )
    ensure
      transport&.close
    end

    it 'rejects a rekey control for the wrong next epoch' do
      secret = 'o' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      channel = RSMP::Secure::Channel.new(secret, role: :responder,
                                                  rsmp_context: secure_channel_context)
      peer_channel = RSMP::Secure::Channel.new(secret, role: :initiator,
                                                       rsmp_context: secure_channel_context)
      transport = RSMP::Secure::Transport.new(
        RSMP::Secure::Transport::Config.new(
          frame_io: nil,
          role: :responder,
          settings: RSMP::Secure.settings({}),
          channel: channel,
          session_builder: nil,
          channel_builder: nil,
          log: nil,
          parent: Async::Task.current
        )
      )
      frame = peer_channel.encrypt_control('kind' => 'rekey_msg1', 'next_epoch' => 2, 'edhoc' => 'msg1'.b)

      expect do
        transport.send(:process_rekey_frame, frame)
      end.to raise_exception(
        RSMP::Secure::FrameError,
        message: be == 'Expected rekey epoch 1, got 2'
      )
    ensure
      transport&.close
    end

    it 'rejects an unsolicited rekey response' do
      secret = 'o' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      channel = RSMP::Secure::Channel.new(secret, role: :initiator,
                                                  rsmp_context: secure_channel_context)
      peer_channel = RSMP::Secure::Channel.new(secret, role: :responder,
                                                       rsmp_context: secure_channel_context)
      transport = RSMP::Secure::Transport.new(
        RSMP::Secure::Transport::Config.new(
          frame_io: nil,
          role: :initiator,
          settings: RSMP::Secure.settings({}),
          channel: channel,
          session_builder: nil,
          channel_builder: nil,
          log: nil,
          parent: Async::Task.current
        )
      )
      frame = peer_channel.encrypt_control('kind' => 'rekey_msg2', 'next_epoch' => 1, 'edhoc' => 'msg2'.b)

      expect do
        transport.send(:process_rekey_frame, frame)
      end.to raise_exception(
        RSMP::HandshakeError,
        message: be == 'Unsolicited secure rekey response'
      )
    ensure
      transport&.close
    end

    it 'rejects a changed credential identity during rekey' do
      secret = 'o' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      channel = RSMP::Secure::Channel.new(secret, role: :initiator,
                                                  rsmp_context: secure_channel_context)
      transport = RSMP::Secure::Transport.new(
        RSMP::Secure::Transport::Config.new(
          frame_io: nil,
          role: :initiator,
          settings: RSMP::Secure.settings({}),
          channel: channel,
          peer_id: 'expected-peer',
          session_builder: nil,
          channel_builder: nil,
          log: nil,
          parent: Async::Task.current
        )
      )
      session = Struct.new(:peer_id).new('different-peer')

      expect do
        transport.send(:validate_rekey_peer!, session)
      end.to raise_exception(
        RSMP::Secure::AuthenticationError,
        message: be == 'Secure rekey authenticated a different credential identity'
      )
    ensure
      transport&.close
    end

    it 'times out rekey and sends exactly one generic authenticated error control' do
      secret = 'o' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      settings = RSMP::Secure.settings({}).merge('rekey_timeout' => 0.01)
      channel = RSMP::Secure::Channel.new(secret, role: :initiator,
                                                  rsmp_context: secure_channel_context)
      peer_channel = RSMP::Secure::Channel.new(secret, role: :responder,
                                                       rsmp_context: secure_channel_context)
      transport = RSMP::Secure::Transport.new(
        RSMP::Secure::Transport::Config.new(
          frame_io: nil,
          role: :initiator,
          settings: settings,
          channel: channel,
          peer_id: 'expected-peer',
          session_builder: -> { Async::Task.current.sleep(1) },
          channel_builder: nil,
          log: nil,
          parent: Async::Task.current
        )
      )
      frames = []
      transport.define_singleton_method(:write_frame) { |frame| frames << frame }

      expect do
        transport.send(:execute_rekey_exchange)
      end.to raise_exception(
        RSMP::HandshakeError,
        message: be(:start_with?, 'EDHOC rekey failed:')
      )
      expect(frames.size).to be == 1
      expect(peer_channel.decrypt_control_frame(frames.first)).to be == {
        'kind' => 'rekey_error',
        'next_epoch' => 1,
        'code' => 'failed'
      }
    ensure
      transport&.close
    end

    it 'rejects a responder acknowledgement encrypted under the old epoch keys' do
      old_secret = 'o' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      new_secret = 'n' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      old_channel = RSMP::Secure::Channel.new(old_secret, role: :initiator,
                                                          rsmp_context: secure_channel_context)
      old_peer_channel = RSMP::Secure::Channel.new(old_secret, role: :responder,
                                                               rsmp_context: secure_channel_context)
      pending_channel = RSMP::Secure::Channel.new(new_secret, role: :initiator, epoch: 1,
                                                              session_id: old_channel.session_id,
                                                              rsmp_context: secure_channel_context)
      transport = RSMP::Secure::Transport.new(
        RSMP::Secure::Transport::Config.new(
          frame_io: nil,
          role: :initiator,
          settings: RSMP::Secure.settings({}),
          channel: old_channel,
          session_builder: nil,
          channel_builder: nil,
          log: nil,
          parent: Async::Task.current
        )
      )
      transport.instance_variable_set(:@pending_rekey_channel, pending_channel)
      forged_ack = old_peer_channel.encrypt_control('kind' => 'rekey_ack', 'next_epoch' => 1)

      expect do
        transport.send(:process_rekey_frame, forged_ack)
      end.to raise_exception(RSMP::Secure::FrameError)
      error = transport.instance_variable_get(:@error)

      expect(error).to be_a(RSMP::Secure::FrameError)
      expect(error.message).to be == 'rekey_ack must be authenticated with the pending new epoch keys'
    ensure
      transport&.close
    end
  end

  it 'connects a site and supervisor through Secure RSMP' do
    Dir.mktmpdir do |dir|
      site_secure, supervisor_secure = secure_settings(dir)
      site_peer = site_secure.fetch('peers').first
      supervisor_peer = supervisor_secure.fetch('peers').first
      port = 13_113
      site_log = StringIO.new
      site_logger = RSMP::Logger.new('stream' => site_log, 'style' => false)
      site_logger.mute('127.0.0.1', port)
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'RN+SI0001',
          'core_version' => '3.3.0',
          'sxls' => {},
          'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => port, 'secure' => public_peer_settings(site_peer) }],
          'secure' => site_secure.except('peers').merge('enabled' => true)
        },
        logger: site_logger,
        log_settings: { 'active' => false }
      )
      supervisor = RSMP::Supervisor.new(
        supervisor_settings: {
          'port' => port,
          'secure' => supervisor_secure.except('peers').merge('required' => true),
          'default' => {
            'core_version' => '3.3.0',
            'sxls' => {}
          },
          'sites' => {
            'RN+SI0001' => {
              'sxls' => {},
              'secure' => public_peer_settings(supervisor_peer)
            }
          }
        },
        log_settings: { 'active' => false }
      )

      with_async_context(context: lambda {
        supervisor.start
        supervisor.ready_condition.wait
        site.start
      }) do
        site_proxy = supervisor.wait_for_site('RN+SI0001', timeout: 3)
        supervisor_proxy = site.wait_for_supervisor('127.0.0.1', timeout: 3)

        site_proxy.wait_for_state(:ready, timeout: 3)
        supervisor_proxy.wait_for_state(:ready, timeout: 3)

        expect(site_proxy.state).to be == :ready
        expect(supervisor_proxy.state).to be == :ready
        expect(site_proxy.schemas).to be == { core: '3.3.0' }
        expect(supervisor_proxy.schemas).to be == { core: '3.3.0' }
        expect(site_proxy.instance_variable_get(:@protocol).authorization_context.role).to be == :site
        expect(supervisor_proxy.instance_variable_get(:@protocol).authorization_context.role).to be == :supervisor
        expect(site_log.string).to be(:include?, 'Secure handshake with peer supervisor complete (initiator, epoch 0)')

        expect(supervisor.revoke_secure_credential!('RN+SI0001')).to be == 1
        expect(supervisor.secure_revocation_list.revoked?('RN+SI0001')).to be == true
        expect(site_proxy.wait_for_state(:disconnected, timeout: 3)).to be == true
        expect(supervisor.restore_secure_credential!('RN+SI0001')).to be == true
      end
    end
  end

  it 'closes a secure RSMP connection after authenticated RSMP schema validation fails' do
    Dir.mktmpdir do |dir|
      site_secure, supervisor_secure = secure_settings(dir)
      site_peer = site_secure.fetch('peers').first
      supervisor_peer = supervisor_secure.fetch('peers').first
      port = 13_117
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'RN+SI0001',
          'core_version' => '3.3.0',
          'sxls' => {},
          'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => port,
                              'secure' => public_peer_settings(site_peer) }],
          'secure' => site_secure.except('peers').merge('enabled' => true)
        },
        log_settings: { 'active' => false }
      )
      supervisor = RSMP::Supervisor.new(
        supervisor_settings: {
          'port' => port,
          'secure' => supervisor_secure.except('peers').merge('required' => true),
          'default' => {
            'core_version' => '3.3.0',
            'sxls' => {}
          },
          'sites' => {
            'RN+SI0001' => {
              'sxls' => {},
              'skip_validation' => ['Watchdog'],
              'secure' => public_peer_settings(supervisor_peer)
            }
          }
        },
        log_settings: { 'active' => false }
      )

      with_async_context(context: lambda {
        supervisor.start
        supervisor.ready_condition.wait
        site.start
      }) do
        site_proxy = supervisor.wait_for_site('RN+SI0001', timeout: 3)
        supervisor_proxy = site.wait_for_supervisor('127.0.0.1', timeout: 3)
        site_proxy.wait_for_state(:ready, timeout: 3)
        supervisor_proxy.wait_for_state(:ready, timeout: 3)

        sender_protocol = supervisor_proxy.instance_variable_get(:@protocol)
        sender_protocol.write_lines(
          JSON.generate(
            'mType' => 'rSMsg',
            'type' => 'Watchdog',
            'mId' => 'invalid-authenticated-watchdog'
          )
        )

        expect(site_proxy.wait_for_state(:disconnected, timeout: 3)).to be == true
      end
    end
  end

  it 'connects two secure sites to one secure supervisor listener with different credentials' do
    Dir.mktmpdir do |dir|
      secure = multi_site_secure_settings(dir)
      port = 13_114
      site1 = RSMP::Site.new(
        site_settings: {
          'site_id' => 'RN+SI0001',
          'core_version' => '3.3.0',
          'sxls' => {},
          'supervisors' => [
            {
              'ip' => '127.0.0.1',
              'port' => port,
              'secure' => secure.fetch(:supervisor_peer)
            }
          ],
          'secure' => secure.fetch(:site1).merge('enabled' => true)
        },
        log_settings: { 'active' => false }
      )
      site2 = RSMP::Site.new(
        site_settings: {
          'site_id' => 'RN+SI0002',
          'core_version' => '3.3.0',
          'sxls' => {},
          'supervisors' => [
            {
              'ip' => '127.0.0.1',
              'port' => port,
              'secure' => secure.fetch(:supervisor_peer)
            }
          ],
          'secure' => secure.fetch(:site2).merge('enabled' => true)
        },
        log_settings: { 'active' => false }
      )
      supervisor = RSMP::Supervisor.new(
        supervisor_settings: {
          'port' => port,
          'secure' => secure.fetch(:supervisor).merge('required' => true),
          'default' => {
            'core_version' => '3.3.0',
            'sxls' => {}
          },
          'sites' => {
            'RN+SI0001' => {
              'sxls' => {},
              'secure' => secure.fetch(:site1_peer)
            },
            'RN+SI0002' => {
              'sxls' => {},
              'secure' => secure.fetch(:site2_peer)
            }
          }
        },
        log_settings: { 'active' => false }
      )

      with_async_context(context: lambda {
        supervisor.start
        supervisor.ready_condition.wait
        site1.start
        site2.start
      }) do
        site1_proxy = supervisor.wait_for_site('RN+SI0001', timeout: 3)
        site2_proxy = supervisor.wait_for_site('RN+SI0002', timeout: 3)
        supervisor1 = site1.wait_for_supervisor('127.0.0.1', timeout: 3)
        supervisor2 = site2.wait_for_supervisor('127.0.0.1', timeout: 3)

        site1_proxy.wait_for_state(:ready, timeout: 3)
        site2_proxy.wait_for_state(:ready, timeout: 3)
        supervisor1.wait_for_state(:ready, timeout: 3)
        supervisor2.wait_for_state(:ready, timeout: 3)

        expect(site1_proxy.state).to be == :ready
        expect(site2_proxy.state).to be == :ready
      end
    end
  end

  it 'connects one secure site to two secure supervisor listeners with different credentials' do
    Dir.mktmpdir do |dir|
      secure = multi_supervisor_secure_settings(dir)
      port1 = 13_115
      port2 = 13_116
      supervisor1 = RSMP::Supervisor.new(
        supervisor_settings: {
          'port' => port1,
          'secure' => secure.fetch(:supervisor1).merge('required' => true),
          'default' => {
            'core_version' => '3.3.0',
            'sxls' => {}
          },
          'sites' => {
            'RN+SI0001' => {
              'sxls' => {},
              'secure' => secure.fetch(:site_peer)
            }
          }
        },
        log_settings: { 'active' => false }
      )
      supervisor2 = RSMP::Supervisor.new(
        supervisor_settings: {
          'port' => port2,
          'secure' => secure.fetch(:supervisor2).merge('required' => true),
          'default' => {
            'core_version' => '3.3.0',
            'sxls' => {}
          },
          'sites' => {
            'RN+SI0001' => {
              'sxls' => {},
              'secure' => secure.fetch(:site_peer)
            }
          }
        },
        log_settings: { 'active' => false }
      )
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'RN+SI0001',
          'core_version' => '3.3.0',
          'sxls' => {},
          'supervisors' => [
            {
              'ip' => '127.0.0.1',
              'port' => port1,
              'secure' => secure.fetch(:supervisor1_peer)
            },
            {
              'ip' => '127.0.0.1',
              'port' => port2,
              'secure' => secure.fetch(:supervisor2_peer)
            }
          ],
          'secure' => secure.fetch(:site).merge('enabled' => true)
        },
        log_settings: { 'active' => false }
      )

      with_async_context(context: lambda {
        supervisor1.start
        supervisor1.ready_condition.wait
        supervisor2.start
        supervisor2.ready_condition.wait
        site.start
      }) do
        site1_proxy = supervisor1.wait_for_site('RN+SI0001', timeout: 3)
        site2_proxy = supervisor2.wait_for_site('RN+SI0001', timeout: 3)
        supervisor1_proxy = site.wait_for_supervisor('127.0.0.1', port: port1, timeout: 3)
        supervisor2_proxy = site.wait_for_supervisor('127.0.0.1', port: port2, timeout: 3)
        site1_proxy.wait_for_state(:ready, timeout: 3)
        site2_proxy.wait_for_state(:ready, timeout: 3)
        supervisor1_proxy.wait_for_state(:ready, timeout: 3)
        supervisor2_proxy.wait_for_state(:ready, timeout: 3)

        expect(site1_proxy.state).to be == :ready
        expect(site2_proxy.state).to be == :ready
        expect(supervisor1_proxy.state).to be == :ready
        expect(supervisor2_proxy.state).to be == :ready
      end
    end
  end
end
