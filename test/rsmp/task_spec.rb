# Define test class at file level (replaces stub_const)
class TaskTest
  include RSMP::Task

  def run
    loop do
      task.sleep 1
    end
  end
end

describe RSMP::Task do
  let(:obj) { TaskTest.new }

  with 'initialize' do
    it 'does not create task' do
      expect(obj.task).to be_nil
    end
  end

  with 'start' do
    it 'creates task' do
      obj.start
      Async::Task.current.sleep(0) # yield to let task start
      expect(obj.task).to be_a(Async::Task)
      expect(obj.task_status).to be == :running
      obj.stop
    end

    it 'calls run' do
      called = false
      mock(obj).replace(:run) do
        called = true
        loop { Async::Task.current.sleep(1) }
      end
      obj.start
      Async::Task.current.sleep(0) # yield to let task start
      expect(called).to be == true
      obj.stop
    end

    it 'can be called several times' do
      obj.start
      obj.start
      Async::Task.current.sleep(0)
      expect(obj.task).to be_a(Async::Task)
      expect(obj.task_status).to be == :running
      obj.stop
    end
  end

  with 'stop' do
    it 'stops the task' do
      obj.start
      obj.stop
      expect(obj.task).to be_nil
      expect(obj.task_status).to be_nil
    end
  end

  with 'restart' do
    it 'raises Restart' do
      obj.start
      Async::Task.current.sleep(0)
      expect(obj.task).to be_a(Async::Task)
      expect(obj.task_status).to be == :running

      expect { obj.restart }.to raise_exception(RSMP::Restart)
      obj.stop
    end
  end
end
