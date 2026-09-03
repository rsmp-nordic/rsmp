require_relative '../support/site_proxy_stub'

describe RSMP::Queue do
  let(:collect_timeout) { 0.01 }

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
  end
end
