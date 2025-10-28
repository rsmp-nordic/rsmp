RSpec.describe RSMP::Queue do
  let(:timeout) { 0.01 }

  describe '#handle_message' do
    it 'queues message' do
      AsyncRSpec.async do |task|
        queue = described_class.new nil, task: task
        queue.receive RSMP::Watchdog.new
        queue.receive RSMP::StatusUpdate.new
        expect(queue.messages.size).to eq(2)
      end
    end
  end

  describe '#wait_for_message' do
    it 'returns already queued message' do
      AsyncRSpec.async do |task|
        queue = described_class.new nil, task: task
        queue.receive RSMP::Watchdog.new
        queue.receive RSMP::StatusUpdate.new

        expect(queue.wait_for_message).to be_a(RSMP::Watchdog)
        expect(queue.wait_for_message).to be_a(RSMP::StatusUpdate)
      end
    end

    it 'returns once messages are received' do
      AsyncRSpec.async do |task|
        queue = described_class.new nil, task: task
        wait_task = task.async do
          got = queue.wait_for_message timeout: timeout
          expect(got).to be_a(RSMP::StatusUpdate)
          expect(queue.messages).to be_empty
        end
        queue.receive RSMP::StatusUpdate.new
        wait_task.wait
      end
    end

    it 'respects filter' do
      AsyncRSpec.async do |task|
        queue = described_class.new nil, task: task, filter: RSMP::Filter.new(type: 'StatusUpdate')
        queue.receive RSMP::Watchdog.new
        queue.receive RSMP::StatusUpdate.new

        expect(queue.wait_for_message).to be_a(RSMP::StatusUpdate)
      end
    end

    it 'times out if no mesage received' do
      AsyncRSpec.async do |task|
        queue = described_class.new nil, task: task
        expect { queue.wait_for_message(timeout: timeout) }.to raise_error(RSMP::TimeoutError)
      end
    end
  end
end
