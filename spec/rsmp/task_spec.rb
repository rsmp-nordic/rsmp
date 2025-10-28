RSpec.describe RSMP::Task do
  before do
    stub_const('TaskTest', Class.new do
      include RSMP::Task

      def run
        loop do
          task.sleep 1
        end
      end
    end)
  end

  let(:obj) { TaskTest.new }

  describe 'initialize' do
    it 'does not create task' do
      expect(obj.task).to be_nil
    end
  end

  describe 'start' do
    it 'creates task' do
      Async(transient: true) do |_task|
        obj.start
        expect(obj.task).to be_a(Async::Task)
        expect(obj.task_status).to eq(:running)
      end
    end

    it 'calls run' do
      Async(transient: true) do |_task|
        allow(obj).to receive(:run).and_call_original
        obj.start
        expect(obj).to have_received(:run)
      end
    end

    it 'can be called several times' do
      Async(transient: true) do |_task|
        obj.start
        obj.start
        expect(obj.task).to be_a(Async::Task)
        expect(obj.task_status).to eq(:running)
      end
    end
  end

  describe 'stop' do
    it 'stops the task' do
      Async(transient: true) do |_task|
        obj.start
        obj.stop
        expect(obj.task).to be_nil
        expect(obj.task_status).to be_nil
      end
    end
  end

  describe 'restart' do
    it 'raises Restart' do
      Async(transient: true) do |_task|
        obj.start
        expect(obj.task).to be_a(Async::Task)
        expect(obj.task_status).to eq(:running)

        obj.task
        expect { obj.restart }.to raise_error(RSMP::Restart)
      end
    end
  end
end
