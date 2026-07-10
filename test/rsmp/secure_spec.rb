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

    def read_exactly(size)
      data = @input.read(size)
      raise EOFError if data.nil? || data.bytesize < size

      data
    end
  end

  def write_secure_file(dir, name, bytes)
    path = File.join(dir, name)
    File.binwrite(path, bytes)
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
    vector = Edhoc::Native.suite0_test_vector
    [site_secure_settings(dir, vector), supervisor_secure_settings(dir, vector)]
  end

  def site_secure_settings(dir, vector)
    {
      'private_key' => write_secure_file(dir, 'site-private.key', vector.fetch(:initiator_private_key)),
      'credential' => write_secure_file(dir, 'site.cred', vector_secure_credential(vector, :initiator, 'RN+SI0001')),
      'peers' => [supervisor_secure_peer(dir, vector)],
      'profile' => RSMP::Secure::PROFILE,
      'handshake_timeout' => 1
    }
  end

  def supervisor_secure_settings(dir, vector)
    {
      'private_key' => write_secure_file(dir, 'supervisor-private.key', vector.fetch(:responder_private_key)),
      'credential' => write_secure_file(dir, 'supervisor-local.cred',
                                        vector_secure_credential(vector, :responder, 'supervisor')),
      'peers' => [site_secure_peer(dir, vector)],
      'profile' => RSMP::Secure::PROFILE,
      'handshake_timeout' => 1
    }
  end

  def supervisor_secure_peer(dir, vector)
    {
      'id' => 'supervisor',
      'public_key' => write_secure_file(dir, 'supervisor.pub', vector.fetch(:responder_public_key)),
      'credential' => write_secure_file(dir, 'supervisor.cred',
                                        vector_secure_credential(vector, :responder, 'supervisor'))
    }
  end

  def site_secure_peer(dir, vector)
    {
      'id' => 'RN+SI0001',
      'public_key' => write_secure_file(dir, 'site.pub', vector.fetch(:initiator_public_key)),
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

  def secure_credential(id, private_key:, public_key:)
    RSMP::Secure::CredentialBundle.create(id: id,
                                          profile: RSMP::Secure::PROFILE,
                                          private_key: private_key,
                                          public_key: public_key)
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
      'handshake_timeout' => 1
    }
  end

  def secure_peer(dir, name, public_key, credential)
    {
      'public_key' => write_secure_file(dir, "#{name}.pub", public_key),
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
      'public_key' => peer['public_key'],
      'credential' => peer['credential']
    }
  end

  def multi_site_secure_settings(dir)
    vector = Edhoc::Native.suite0_test_vector
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
    vector = Edhoc::Native.suite0_test_vector
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

  it 'describes enabled secure settings for logs' do
    expect(RSMP::Secure.log_summary('enabled' => true)).to be == 'Secure profile rsmp-secure-v1'
    expect(RSMP::Secure.log_summary('required' => true)).to be == 'Secure profile rsmp-secure-v1'
    expect(RSMP::Secure.log_summary(nil)).to be_nil
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:status)).to be == :implemented
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:edhoc_cipher_suite)).to be == 4
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:edhoc_aead)).to be == 'ChaCha20-Poly1305'
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:data_protection)).to be == 'COSE_Encrypt0'
    expect(RSMP::Secure.profile_metadata('rsmp-secure-v1').fetch(:cose_algorithm)).to be == 24
    expect(RSMP::Secure.implemented_profile?('rsmp-secure-test-dev')).to be == false
    expect(RSMP::Secure.implemented_profile?('rsmp-secure-v1')).to be == true
    expect(RSMP::Secure.handshake_complete_summary({ 'enabled' => true }, role: :initiator)).to be == 'Secure handshake complete (initiator, epoch 0)'
    expect(RSMP::Secure.handshake_complete_summary({ 'enabled' => true }, role: :initiator, peer_id: 'RN+SI0002')).to be == 'Secure handshake with peer RN+SI0002 complete (initiator, epoch 0)'
    expect(RSMP::Secure.rekey_started_summary({ 'enabled' => true }, role: :initiator, epoch: 1)).to be == 'Secure rekey started (initiator, epoch 1)'
    expect(RSMP::Secure.rekey_started_summary({ 'enabled' => true }, role: :initiator, epoch: 1, peer_id: 'RN+SI0002')).to be == 'Secure rekey with peer RN+SI0002 started (initiator, epoch 1)'
    expect(RSMP::Secure.settings({})['rekey_after_messages']).to be == 1_000_000
    expect(RSMP::Secure.settings({})['rekey_after_seconds']).to be == 7_200
    expect(RSMP::Secure.settings({})['min_rekey_interval']).to be == 60
  end

  it 'rejects unsupported secure profiles with a clear error' do
    expect do
      RSMP::Secure.validate_profile_name!('rsmp-secure-unknown')
    end.to raise_exception(RSMP::ConfigurationError,
                           message: be == 'Unsupported secure profile "rsmp-secure-unknown"')
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
        'public_key' => 'supervisor.pub',
        'credential' => 'supervisor.cred'
      }
    }

    merged = RSMP::Secure.site_peer_settings({ 'secure' => local }, endpoint)

    expect(merged['private_key']).to be == 'site-private.key'
    expect(merged['credential']).to be == 'site.cred'
    expect(merged['peers']).to be == [{
      'id' => 'supervisor-a',
      'public_key' => 'supervisor.pub',
      'credential' => 'supervisor.cred',
      'supervisor_id' => nil
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
      'public_key' => 'secure/supervisor.pub',
      'credential' => 'secure/supervisor.cred',
      'supervisor_id' => nil
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
        'public_key' => 'secure/RN+SI0001.pub',
        'credential' => 'secure/RN+SI0001.cred',
        'site_id' => 'RN+SI0001'
      },
      {
        'id' => 'RN+SI0002',
        'public_key' => 'secure/RN+SI0002.pub',
        'credential' => 'secure/RN+SI0002.cred',
        'site_id' => 'RN+SI0002'
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
      'public_key' => 'secure/RN+SI0002.pub',
      'credential' => 'secure/RN+SI0002.cred',
      'site_id' => 'RN+SI0002'
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
      'public_key' => 'secure/RN+SI0002.pub',
      'credential' => 'secure/RN+SI0002.cred',
      'supervisor_id' => nil
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
      vector = Edhoc::Native.suite0_test_vector
      FileUtils.mkdir_p(secure_dir)
      File.binwrite(File.join(secure_dir, 'supervisor.private.key'), vector.fetch(:responder_private_key))
      File.binwrite(File.join(secure_dir, 'supervisor.cred'),
                    vector_secure_credential(vector, :responder, 'supervisor'))
      File.binwrite(File.join(secure_dir, 'RN+SI0001.cred'),
                    vector_secure_credential(vector, :initiator, 'RN+SI0001'))

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
        message: be == "secure peer RN+SI0001 public_key file not found: #{File.join(dir, 'secure/RN+SI0001.pub')}"
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
            'public_key' => 'site1.pub',
            'credential' => 'site1.cred'
          }
        },
        'RN+SI0002' => {
          'secure' => {
            'public_key' => 'site2.pub',
            'credential' => 'site2.cred'
          }
        }
      }
    )

    expect(settings['peers'].map { |peer| peer['id'] }).to be == %w[RN+SI0001 RN+SI0002]
  end

  it 'resolves secure file paths relative to the config file directory' do
    Dir.mktmpdir do |dir|
      vector = Edhoc::Native.suite0_test_vector
      config_dir = File.join(dir, 'config')
      secure_dir = File.join(config_dir, 'secure')
      FileUtils.mkdir_p(secure_dir)

      File.binwrite(File.join(secure_dir, 'RN+SI0001.private.key'), vector.fetch(:initiator_private_key))
      File.binwrite(File.join(secure_dir, 'RN+SI0001.cred'),
                    vector_secure_credential(vector, :initiator, 'RN+SI0001'))
      File.binwrite(File.join(secure_dir, 'supervisor.pub'), vector.fetch(:responder_public_key))
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
              public_key: secure/supervisor.pub
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
  end

  with RSMP::Secure::CredentialBundle do
    it 'encodes and verifies a deterministic v1 credential bundle' do
      vector = Edhoc::Native.suite0_test_vector
      encoded = RSMP::Secure::CredentialBundle.create(
        id: 'RN+SI0001',
        profile: RSMP::Secure::V1_PROFILE,
        private_key: vector.fetch(:initiator_private_key),
        public_key: vector.fetch(:initiator_public_key)
      )
      bundle = RSMP::Secure::CredentialBundle.decode(encoded, expected_profile: RSMP::Secure::V1_PROFILE)
      cose_sign1 = RSMP::Secure::Cbor.decode(encoded)
      protected_headers, unprotected_headers, payload, signature = cose_sign1

      expect(RSMP::Secure::CredentialBundle.id(bundle)).to be == 'RN+SI0001'
      expect(RSMP::Secure::CredentialBundle.public_key(bundle)).to be == vector.fetch(:initiator_public_key)
      expect(RSMP::Secure::CredentialBundle.kid(bundle).bytesize).to be == 16
      expect(RSMP::Secure::CredentialBundle.edhoc_credential(bundle)).to be == RSMP::Secure::CredentialBundle.ccs_credential(
        'RN+SI0001',
        vector.fetch(:initiator_public_key),
        RSMP::Secure::CredentialBundle.kid(bundle)
      )
      expect(RSMP::Secure::Cbor.decode(protected_headers)).to be == { 1 => -8 }
      expect(unprotected_headers).to be == {}
      expect(RSMP::Secure::Cbor.decode(payload)).to be == bundle
      expect(signature.bytesize).to be == 64
      expect(RSMP::Secure::CredentialBundle.encode(bundle)).to be == payload
    end

    it 'rejects tampered v1 credential bundles' do
      vector = Edhoc::Native.suite0_test_vector
      encoded = RSMP::Secure::CredentialBundle.create(
        id: 'RN+SI0001',
        profile: RSMP::Secure::V1_PROFILE,
        private_key: vector.fetch(:initiator_private_key),
        public_key: vector.fetch(:initiator_public_key)
      )
      cose_sign1 = RSMP::Secure::Cbor.decode(encoded)
      bundle = RSMP::Secure::Cbor.decode(cose_sign1.fetch(2))
      tampered = cose_sign1.dup
      tampered[2] = RSMP::Secure::Cbor.encode(bundle.merge('id' => 'RN+SI9999'))

      expect do
        RSMP::Secure::CredentialBundle.decode(RSMP::Secure::CredentialBundle.encode(tampered),
                                              expected_profile: RSMP::Secure::V1_PROFILE)
      end.to raise_exception(RSMP::Secure::ConfigurationError,
                             message: be == 'credential bundle "RN+SI9999" signature is invalid')
    end

    it 'verifies peer credentials with the configured trust key' do
      vector = Edhoc::Native.suite0_test_vector
      attacker = generated_secure_identity('attacker')
      encoded = RSMP::Secure::CredentialBundle.create(
        id: 'attacker',
        profile: RSMP::Secure::V1_PROFILE,
        private_key: attacker.fetch(:private_key),
        public_key: attacker.fetch(:public_key)
      )

      expect do
        RSMP::Secure::CredentialBundle.decode(
          encoded,
          expected_profile: RSMP::Secure::V1_PROFILE,
          trusted_public_key: vector.fetch(:initiator_public_key)
        )
      end.to raise_exception(
        RSMP::Secure::ConfigurationError,
        message: be == 'credential bundle "attacker" signature is invalid'
      )
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

    it 'rejects truncated frames' do
      bytes = "#{[10].pack('N')}xx"

      expect do
        RSMP::Secure::FrameIO.new(SecureMemoryStream.new(bytes), max_frame_size: 100).read
      end.to raise_exception(RSMP::Secure::FrameError)
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
    it 'rejects direct top-level public peer credentials without a resolved peer list' do
      Dir.mktmpdir do |dir|
        vector = Edhoc::Native.suite0_test_vector
        settings = {
          'private_key' => write_secure_file(dir, 'site-private.key', vector.fetch(:initiator_private_key)),
          'credential' => write_secure_file(dir, 'site.cred',
                                            vector_secure_credential(vector, :initiator, 'RN+SI0001')),
          'public_key' => write_secure_file(dir, 'supervisor.pub', vector.fetch(:responder_public_key))
        }

        expect do
          RSMP::Secure::Protocol.new(SecureMemoryStream.new, role: :initiator, settings: settings)
        end.to raise_exception(RSMP::Secure::ConfigurationError)
      end
    end

    it 'reports when EDHOC rejects an unknown credential' do
      Dir.mktmpdir do |dir|
        vector = Edhoc::Native.suite0_test_vector
        unknown_site = generated_secure_identity('RN+SI0002')
        site_settings = {
          'private_key' => write_secure_file(dir, 'site-private.key', unknown_site.fetch(:private_key)),
          'credential' => write_secure_file(dir, 'unknown-site.cred', unknown_site.fetch(:credential)),
          'peers' => [{
            'id' => 'supervisor',
            'public_key' => write_secure_file(dir, 'supervisor.pub', vector.fetch(:responder_public_key)),
            'credential' => write_secure_file(dir, 'supervisor.cred',
                                              vector_secure_credential(vector, :responder, 'supervisor'))
          }],
          'handshake_timeout' => 1
        }
        supervisor_settings = {
          'private_key' => write_secure_file(dir, 'supervisor-private.key', vector.fetch(:responder_private_key)),
          'credential' => write_secure_file(dir, 'supervisor.cred',
                                            vector_secure_credential(vector, :responder, 'supervisor')),
          'peers' => [{
            'id' => 'RN+SI0001',
            'public_key' => write_secure_file(dir, 'site.pub', vector.fetch(:initiator_public_key)),
            'credential' => write_secure_file(dir, 'site.cred',
                                              vector_secure_credential(vector, :initiator, 'RN+SI0001'))
          }],
          'handshake_timeout' => 1
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

    it 'reports legacy JSON sent to a secure responder as a handshake error' do
      Dir.mktmpdir do |dir|
        vector = Edhoc::Native.suite0_test_vector
        settings = supervisor_secure_settings(dir, vector)
        legacy_packet = %({"mType":"rSMsg","type":"Version"}\f)
        protocol = RSMP::Secure::Protocol.new(
          SecureMemoryStream.new(legacy_packet),
          role: :responder,
          settings: settings
        )

        expect do
          protocol.handshake!
        end.to raise_exception(
          RSMP::HandshakeError,
          message: be(:include?, 'expected a secure CBOR frame')
        )
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

    it 'runs the v1 profile with CBOR credential bundles and exchanges encrypted RSMP messages' do
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

        pre_rekey = {
          'mType' => 'rSMsg',
          'type' => 'Watchdog',
          'mId' => '36f85650-ee72-42b1-a097-0f4f48183ef5',
          'wTs' => '2026-07-07T13:15:00.000Z'
        }
        site.write_lines(JSON.generate(pre_rekey))
        expect(JSON.parse(supervisor.read_line)).to be == pre_rekey

        session_id = site.channel.session_id
        expect(supervisor.channel.session_id).to be == session_id

        expect(site.rekey!).to be == true
        expect(site.channel.epoch).to be == 1
        expect(supervisor.channel.epoch).to be == 1
        expect(site.channel.session_id).to be == session_id
        expect(supervisor.channel.session_id).to be == session_id
        expect(site.channel.instance_variable_get(:@recv_idx)).to be == 1
        expect(supervisor.channel.instance_variable_get(:@send_idx)).to be == 1

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

    it 'rejects manual rekey from the responder' do
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

        error = nil
        begin
          supervisor.rekey!
        rescue RSMP::Secure::FrameError => e
          error = e
        end

        expect(error).to be_a(RSMP::Secure::FrameError)
        expect(error.message).to be == 'Secure responder cannot initiate rekey'

        expect(site.channel.epoch).to be == 0
        expect(supervisor.channel.epoch).to be == 0
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

        write_error = nil
        begin
          site.write_lines(JSON.generate('mType' => 'rSMsg', 'type' => 'Watchdog'))
        rescue RSMP::Secure::AuthenticationError => e
          write_error = e
        end

        expect(write_error).to be == read_error
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
          'rekey_after_messages' => 1,
          'rekey_after_seconds' => nil,
          'min_rekey_interval' => 0
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
        expect(site_logs).to be == [
          ['Secure handshake with peer supervisor complete (initiator, epoch 0)', { level: :info }],
          ['Secure rekey with peer supervisor started (initiator, epoch 1)', { level: :info }],
          ['Secure handshake with peer supervisor complete (initiator, epoch 1)', { level: :info }]
        ]
        expect(supervisor_logs).to be == [
          ['Secure handshake with peer RN+SI0001 complete (responder, epoch 0)', { level: :info }],
          ['Secure rekey with peer RN+SI0001 started (responder, epoch 1)', { level: :info }],
          ['Secure handshake with peer RN+SI0001 complete (responder, epoch 1)', { level: :info }]
        ]
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
          'rekey_after_messages' => 1,
          'rekey_after_seconds' => nil,
          'min_rekey_interval' => 60
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
            'rekey_after_messages' => nil,
            'rekey_after_seconds' => 10,
            'min_rekey_interval' => 0
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
            'rekey_after_messages' => 1,
            'rekey_after_seconds' => 10,
            'min_rekey_interval' => 0
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

    it 'holds new-epoch data until an in-progress responder rekey installs the new channel' do
      old_secret = 'o' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      new_secret = 'n' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      old_channel = RSMP::Secure::Channel.new(old_secret, role: :responder,
                                                          rsmp_context: secure_channel_context)
      new_channel = RSMP::Secure::Channel.new(new_secret, role: :responder, epoch: 1,
                                                          session_id: old_channel.session_id,
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
      reader = Async::Task.current.async { transport.send(:enqueue_plaintext, frame) }
      Async::Task.current.sleep 0.01
      expect(reader).not.to be(:complete?)

      transport.instance_variable_set(:@channel, new_channel)
      transport.instance_variable_set(:@rekeying, false)
      transport.instance_variable_get(:@rekey_done).signal

      reader.wait
      expect(JSON.parse(transport.read_line)).to be == message
    ensure
      reader&.stop
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

      transport.send(:process_rekey_frame, forged_ack)
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
        expect(site_log.string).to be(:include?, 'Secure handshake with peer supervisor complete (initiator, epoch 0)')
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
