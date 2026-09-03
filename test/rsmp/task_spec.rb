# Define test class at file level (replaces stub_const)
class TaskTest
  include RSMP::Task

  def run
    loop do
      task.sleep 1
    end
  end
end

class FaultyTaskTest
  include RSMP::Task

  attr_reader :trigger

  def initialize
    @trigger = Async::Notification.new
  end

  def run
    trigger.wait
    nil.missing_validator_method
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
      expect(obj.task).to be_a(Async::Task)
      expect(obj.task_status).to be == :cancelled
    end
  end

  with 'restart' do
    it 'resolves an explicit termination value' do
      obj.start
      Async::Task.current.sleep(0)
      expect(obj.task).to be_a(Async::Task)
      expect(obj.task_status).to be == :running

      obj.restart
      termination = obj.wait_for_termination
      expect(termination.success?).to be == true
      expect(termination.value).to be_a(RSMP::Termination)
      expect(termination.value.reason).to be == :restart
      obj.stop
    end
  end

  with 'unexpected failures' do
    it 'preserves the original exception through wait' do
      faulty = FaultyTaskTest.new
      faulty.start
      waiting = Async::Task.current.async do
        expect { faulty.wait }.to raise_exception(
          NoMethodError,
          message: be =~ /missing_validator_method/
        )
      end
      faulty.trigger.signal
      waiting.wait
    end
  end
end
