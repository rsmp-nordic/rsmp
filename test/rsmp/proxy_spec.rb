require_relative '../support/site_proxy_stub'

describe RSMP::Proxy do
  let(:options) { {} }
  let(:proxy) { subject.new options }

  with '#wait_for_state' do
    it 'wakes up' do
      task = Async::Task.current
      subtask = task.async do |_subtask|
        proxy.wait_for_state :connected, timeout: 0.001
      end
      proxy.state = :connected
      expect(subtask.wait).to be == true
    end

    it 'accepts array of states and returns current state' do
      task = Async::Task.current
      subtask = task.async do |_subtask|
        state = proxy.wait_for_state %i[ok ready], timeout: 0.001
        expect(state).to be == :ready
      end
      proxy.state = :ready
      subtask.result
    end

    it 'times out' do
      expect do
        proxy.wait_for_state :connected, timeout: 0.001
      end.to raise_exception(RSMP::TimeoutError)
    end

    it 'returns immediately if state is already correct' do
      proxy.state = :disconnected
      proxy.instance_variable_set(:@state_condition, Async::Notification.new)
      result = proxy.wait_for_state :disconnected, timeout: 0.001
      expect(result).to be == true
    end
  end

  with '#wait_for_condition without block' do
    it 'wakes up' do
      task = Async::Task.current
      condition = Async::Notification.new
      subtask = task.async do |_subtask|
        result = proxy.wait_for_condition condition, timeout: 0.001
        expect(result).to be_truthy
      end
      condition.signal
      subtask.result
    end

    it 'times out' do
      condition = Async::Notification.new
      expect do
        proxy.wait_for_condition condition, timeout: 0.001
      end.to raise_exception(RSMP::TimeoutError)
    end
  end

  with '#wait_for_condition with block' do
    it 'wakes up' do
      task = Async::Task.current
      condition = Async::Notification.new
      result_condition = Async::Notification.new
      result = nil
      subtask = task.async do |_subtask|
        proxy.wait_for_condition condition, timeout: 1 do |state|
          result = (state == :banana)
          result_condition.signal
          result
        end
      end
      condition.signal :pear
      result_condition.wait
      expect(result).to be == false

      condition.signal :apple
      result_condition.wait
      expect(result).to be == false

      condition.signal :banana
      result_condition.wait
      expect(result).to be == true

      subtask.result
    end
  end

  with 'version_meets_requirement?' do
    it 'is equal to' do
      expect(subject.version_meets_requirement?('1.0.9', '1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.10', '1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.11', '1.0.10')).to be == false
    end

    it 'is greater than' do
      expect(subject.version_meets_requirement?('1.0.9', '>1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.10', '>1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.11', '>1.0.10')).to be == true
    end

    it 'is greater than or equal to' do
      expect(subject.version_meets_requirement?('1.0.9', '>=1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.10', '>=1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.11', '>=1.0.10')).to be == true
    end

    it 'is less than' do
      expect(subject.version_meets_requirement?('1.0.9', '<1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.10', '<1.0.10')).to be == false
      expect(subject.version_meets_requirement?('1.0.11', '<1.0.10')).to be == false
    end

    it 'is less than or equal to' do
      expect(subject.version_meets_requirement?('1.0.9', '<=1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.10', '<=1.0.10')).to be == true
      expect(subject.version_meets_requirement?('1.0.11', '<=1.0.10')).to be == false
    end

    it 'takes a list of conditions' do
      expect(subject.version_meets_requirement?('1.0.9', ['>=1.0.10', '<1.0.12'])).to be == false
      expect(subject.version_meets_requirement?('1.0.10', ['>=1.0.10', '<1.0.12'])).to be == true
      expect(subject.version_meets_requirement?('1.0.11', ['>=1.0.10', '<1.0.12'])).to be == true
      expect(subject.version_meets_requirement?('1.0.12', ['>=1.0.10', '<1.0.12'])).to be == false
    end
  end
end
