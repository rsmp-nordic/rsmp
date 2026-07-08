require 'stringio'
require 'timecop'
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

  def with_mocked_process_clock
    previous = Timecop.mock_process_clock?
    Timecop.mock_process_clock = true
    yield
  ensure
    Timecop.return
    Timecop.mock_process_clock = previous
  end

  it 'describes enabled secure settings for logs' do
    expect(RSMP::Secure.log_summary('enabled' => true)).to be == 'Secure RSMP enabled using profile rsmp-secure-suite0-dev'
    expect(RSMP::Secure.log_summary('required' => true)).to be == 'Secure RSMP enabled using profile rsmp-secure-suite0-dev'
    expect(RSMP::Secure.log_summary(nil)).to be_nil
    expect(RSMP::Secure.handshake_complete_summary({ 'enabled' => true }, role: :initiator)).to be == 'Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (initiator, epoch 0)'
    expect(RSMP::Secure.rekey_started_summary({ 'enabled' => true }, role: :initiator, epoch: 1)).to be == 'Secure RSMP E2E rekey started using profile rsmp-secure-suite0-dev (initiator, epoch 1)'
    expect(RSMP::Secure.settings({})['rekey_after_messages']).to be == 1_000_000
    expect(RSMP::Secure.settings({})['rekey_after_seconds']).to be == 7_200
    expect(RSMP::Secure.settings({})['min_rekey_interval']).to be == 60
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

    it 'encrypts rekey control frames with distinct frame type authentication' do
      secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
      initiator = RSMP::Secure::Channel.new(secret, role: :initiator)
      responder = RSMP::Secure::Channel.new(secret, role: :responder)

      frame = initiator.encrypt_control('kind' => 'rekey_request', 'next_epoch' => 1)

      expect(responder.decrypt_control_frame(frame)).to be == {
        'kind' => 'rekey_request',
        'next_epoch' => 1
      }

      data_like = frame.merge('type' => 'data')
      expect do
        RSMP::Secure::Channel.new(secret, role: :responder).decrypt_frame(data_like)
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

        expect(site_logs).to be == [['Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (initiator, epoch 0)', { level: :info }]]
        expect(supervisor_logs).to be == [['Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (responder, epoch 0)', { level: :info }]]

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

        expect(site.rekey!).to be == true
        expect(site.channel.epoch).to be == 1
        expect(supervisor.channel.epoch).to be == 1

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
        frame['ct'] = frame.fetch('ct').dup.tap { |ct| ct.setbyte(ct.bytesize - 1, ct.getbyte(ct.bytesize - 1) ^ 0x01) }
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
          ['Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (initiator, epoch 0)', { level: :info }],
          ['Secure RSMP E2E rekey started using profile rsmp-secure-suite0-dev (initiator, epoch 1)', { level: :info }],
          ['Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (initiator, epoch 1)', { level: :info }]
        ]
        expect(supervisor_logs).to be == [
          ['Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (responder, epoch 0)', { level: :info }],
          ['Secure RSMP E2E rekey started using profile rsmp-secure-suite0-dev (responder, epoch 1)', { level: :info }],
          ['Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (responder, epoch 1)', { level: :info }]
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
        expect(site_logs.count { |entry| entry.first.include?('rekey started') }).to be == 1
        expect(site_logs).to be(:include?, ['Secure RSMP E2E rekey started using profile rsmp-secure-suite0-dev (initiator, epoch 1)', { level: :info }])
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
          expect(site_logs.count { |entry| entry.first.include?('rekey started') }).to be == 1
          expect(site_logs).to be(:include?, ['Secure RSMP E2E rekey started using profile rsmp-secure-suite0-dev (initiator, epoch 1)', { level: :info }])
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
      old_channel = RSMP::Secure::Channel.new(old_secret, role: :responder)
      new_channel = RSMP::Secure::Channel.new(new_secret, role: :responder, epoch: 1, session_id: old_channel.session_id)
      peer_channel = RSMP::Secure::Channel.new(new_secret, role: :initiator, epoch: 1, session_id: old_channel.session_id)
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
        site_proxy = supervisor.wait_for_site('RN+SI0001', timeout: 3)
        supervisor_proxy = site.wait_for_supervisor('127.0.0.1', timeout: 3)

        site_proxy.wait_for_state(:ready, timeout: 3)
        supervisor_proxy.wait_for_state(:ready, timeout: 3)

        expect(site_proxy.state).to be == :ready
        expect(supervisor_proxy.state).to be == :ready
        expect(site_proxy.schemas).to be == { core: '3.3.0' }
        expect(supervisor_proxy.schemas).to be == { core: '3.3.0' }
        expect(site_log.string).to be(:include?, 'Secure RSMP E2E handshake complete using profile rsmp-secure-suite0-dev (initiator, epoch 0)')
      end
    end
  end
end
