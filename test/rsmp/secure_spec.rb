require 'stringio'
require 'tmpdir'
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

  def secure_settings(dir)
    vector = Edhoc::Native.suite0_test_vector
    site = {
      'private_key' => write_secure_file(dir, 'site-private.key', vector.fetch(:initiator_private_key)),
      'credential' => write_secure_file(dir, 'site.cred', vector.fetch(:initiator_credential)),
      'peer_public_key' => write_secure_file(dir, 'supervisor.pub', vector.fetch(:responder_public_key)),
      'peer_credential' => write_secure_file(dir, 'supervisor.cred', vector.fetch(:responder_credential)),
      'handshake_timeout' => 1
    }
    supervisor = {
      'private_key' => write_secure_file(dir, 'supervisor-private.key', vector.fetch(:responder_private_key)),
      'credential' => write_secure_file(dir, 'supervisor.cred', vector.fetch(:responder_credential)),
      'peer_public_key' => write_secure_file(dir, 'site.pub', vector.fetch(:initiator_public_key)),
      'peer_credential' => write_secure_file(dir, 'site.cred', vector.fetch(:initiator_credential)),
      'handshake_timeout' => 1
    }
    [site, supervisor]
  end

  it 'describes enabled secure settings for logs' do
    expect(RSMP::Secure.log_summary('enabled' => true)).to be == 'Secure RSMP enabled using profile rsmp-secure-suite0-dev'
    expect(RSMP::Secure.log_summary('required' => true)).to be == 'Secure RSMP enabled using profile rsmp-secure-suite0-dev'
    expect(RSMP::Secure.log_summary(nil)).to be_nil
    expect(RSMP::Secure.handshake_complete_summary({ 'enabled' => true }, role: :initiator)).to be == 'Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (initiator)'
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

  with RSMP::Secure::FrameIO do
    it 'writes and reads a length-prefixed CBOR frame' do
      write_stream = SecureMemoryStream.new
      RSMP::Secure::FrameIO.new(write_stream, max_frame_size: 100).write(
        'v' => 1,
        'type' => 'data',
        'ct' => 'abc'.b
      )

      frame = RSMP::Secure::FrameIO.new(SecureMemoryStream.new(write_stream.written), max_frame_size: 100).read

      expect(frame).to be == { 'ct' => 'abc'.b, 'type' => 'data', 'v' => 1 }
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
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator)
      responder = RSMP::Secure::Channel.new(secret, role: :responder)
      plaintext = RSMP::Secure::Cbor.encode('mType' => 'rSMsg', 'type' => 'Watchdog')

      frame = initiator.encrypt_payload(plaintext)

      expect(RSMP::Secure::Cbor.decode(responder.decrypt_frame(frame))).to be == {
        'mType' => 'rSMsg',
        'type' => 'Watchdog'
      }
    end

    it 'rejects replayed data indices' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator)
      responder = RSMP::Secure::Channel.new(secret, role: :responder)
      frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))

      responder.decrypt_frame(frame)

      expect do
        responder.decrypt_frame(frame)
      end.to raise_exception(RSMP::Secure::ReplayError)
    end

    it 'rejects authentication failures' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator)
      responder = RSMP::Secure::Channel.new(secret, role: :responder)
      frame = initiator.encrypt_payload(RSMP::Secure::Cbor.encode('ok' => true))
      frame['ct'] = frame.fetch('ct').dup.tap { |ct| ct.setbyte(ct.bytesize - 1, ct.getbyte(ct.bytesize - 1) ^ 0x01) }

      expect do
        responder.decrypt_frame(frame)
      end.to raise_exception(RSMP::Secure::AuthenticationError)
    end
  end

  with RSMP::Secure::Protocol do
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

        expect(site_logs).to be == [['Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (initiator)', { level: :info }]]
        expect(supervisor_logs).to be == [['Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (responder)', { level: :info }]]

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
        site_io&.close
        supervisor_io&.close
      end
    end
  end

  it 'connects a site and supervisor through Secure RSMP' do
    Dir.mktmpdir do |dir|
      site_secure, supervisor_secure = secure_settings(dir)
      port = 13_113
      site_log = StringIO.new
      site_logger = RSMP::Logger.new('stream' => site_log, 'style' => false)
      site_logger.mute('127.0.0.1', port)
      site = RSMP::Site.new(
        site_settings: {
          'site_id' => 'RN+SI0001',
          'core_version' => '3.3.0',
          'sxls' => {},
          'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => port }],
          'secure' => site_secure.merge('enabled' => true)
        },
        logger: site_logger,
        log_settings: { 'active' => false }
      )
      supervisor = RSMP::Supervisor.new(
        supervisor_settings: {
          'port' => port,
          'default' => {
            'core_version' => '3.3.0',
            'sxls' => {},
            'secure' => supervisor_secure.merge('required' => true)
          }
        },
        log_settings: { 'active' => false }
      )

      with_async_context(context: lambda {
        supervisor.start
        supervisor.ready_condition.wait
        site.start
      }) do
        site_proxy = supervisor.wait_for_site('RN+SI0001', timeout: 1)
        supervisor_proxy = site.wait_for_supervisor('127.0.0.1', timeout: 1)

        site_proxy.wait_for_state(:ready, timeout: 1)
        supervisor_proxy.wait_for_state(:ready, timeout: 1)

        expect(site_proxy.state).to be == :ready
        expect(supervisor_proxy.state).to be == :ready
        expect(site_proxy.schemas).to be == { core: '3.3.0' }
        expect(supervisor_proxy.schemas).to be == { core: '3.3.0' }
        expect(site_log.string).to be(:include?, 'Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (initiator)')
      end
    end
  end
end
