describe RSMP::Supervisor do
  def start_socket_supervisor
    supervisor = RSMP::Supervisor.new(
      supervisor_settings: { 'port' => 13_119, 'ips' => 'all',
                             'default' => { 'sxls' => { 'tlc' => '1.2.1' } } },
      log_settings: { 'active' => false }
    )
    supervisor.start
    supervisor
  end

  def send_socket_version(socket)
    protocol = RSMP::Protocol.new(IO::Stream::Buffered.new(socket))
    protocol.write_lines(JSON.generate(
                           'mType' => 'rSMsg', 'type' => 'Version', 'mId' => SecureRandom.uuid,
                           'RSMP' => [{ 'vers' => '3.2.2' }], 'siteId' => [{ 'sId' => 'TEST' }],
                           'SXL' => '1.2.1'
                         ))
    # Receiving the response ensures a proxy exists and has started its reader.
    protocol.read_line
    protocol.read_line
  end

  def expect_socket_eof(socket)
    # Read from the peer itself: local closed? and lifecycle state are insufficient.
    expect do
      Async::Task.current.with_timeout(0.5) { loop { socket.readpartial(4096) } }
    end.to raise_exception(EOFError)
  end

  %i[stop disconnect].each do |operation|
    it "delivers TCP EOF immediately on #{operation} with an active reader" do
      supervisor = start_socket_supervisor
      socket = IO::Endpoint.tcp('127.0.0.1', 13_119).connect
      Async::Task.current.with_timeout(1) { send_socket_version(socket) }

      if operation == :stop
        supervisor.stop
      else
        supervisor.proxies.first.disconnect!
      end

      expect_socket_eof(socket)
    ensure
      socket&.close
      supervisor&.stop
    end
  end

  it 'delivers TCP EOF when stopped while waiting for the first Version message' do
    supervisor = start_socket_supervisor
    socket = IO::Endpoint.tcp('127.0.0.1', 13_119).connect
    Async::Task.current.sleep 0.01
    supervisor.stop
    expect_socket_eof(socket)
  ensure
    socket&.close
    supervisor&.stop
  end
end
