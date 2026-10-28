require_relative '../support/site_proxy_stub'

describe RSMP::Queue do
  let(:collect_timeout) { 0.01 }

  with 'receiving lifecycle' do
    it 'starts receiving, retains early messages, and stops receiving' do
      proxy = RSMP::SiteProxyStub.new Async::Task.current
      queue = subject.new proxy
      queue.start
      first = RSMP::Watchdog.new
      proxy.distribute first
      queue.stop
      proxy.distribute RSMP::Watchdog.new

      expect(queue.wait_for_message!.equal?(first)).to be == true
      expect(queue.messages).to be == []
      expect(proxy.receivers).to be == []
    end
  end

  with '#handle_message' do
    it 'queues message' do
      queue = subject.new nil
      queue.receive RSMP::Watchdog.new
      queue.receive RSMP::StatusUpdate.new
      expect(queue.messages.size).to be == 2
    end
  end

  with '#wait_for_message' do
    it 'returns already queued message' do
      queue = subject.new nil
      queue.receive RSMP::Watchdog.new
      queue.receive RSMP::StatusUpdate.new

      expect(queue.wait_for_message.value).to be_a(RSMP::Watchdog)
      expect(queue.wait_for_message.value).to be_a(RSMP::StatusUpdate)
    end

    it 'returns once messages are received' do
      task = Async::Task.current
      queue = subject.new nil
      wait_task = task.async do
        got = queue.wait_for_message timeout: collect_timeout
        expect(got.success?).to be == true
        expect(got.value).to be_a(RSMP::StatusUpdate)
        expect(queue.messages).to be(:empty?)
      end
      queue.receive RSMP::StatusUpdate.new
      wait_task.wait
    end

    it 'respects filter' do
      queue = subject.new nil, filter: RSMP::Filter.new(type: 'StatusUpdate')
      queue.receive RSMP::Watchdog.new
      queue.receive RSMP::StatusUpdate.new

      expect(queue.wait_for_message.value).to be_a(RSMP::StatusUpdate)
    end

    it 'times out if no message received' do
      queue = subject.new nil
      result = queue.wait_for_message(timeout: collect_timeout)
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :timeout
      expect { queue.wait_for_message!(timeout: collect_timeout) }.to raise_exception(RSMP::OperationError)
    end

    it 'converts an outer timeout when no queue timeout was supplied' do
      queue = subject.new nil
      result = Async::Task.current.with_timeout(collect_timeout) { queue.wait_for_message }
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :timeout
      expect(result.failure.cause).to be_a(Async::TimeoutError)

      begin
        Async::Task.current.with_timeout(collect_timeout) { queue.wait_for_message! }
      rescue RSMP::OperationError => e
        failure = e.failure
      end
      expect(failure.code).to be == :timeout
      expect(failure.cause).to be_a(Async::TimeoutError)
    end
  end
end
