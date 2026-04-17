describe RSMP::CommandResponseCollector do
  let(:collect_timeout) { 0.01 }
  let(:want) do
    {
      m5: { 'cCI' => 'M0005', 'n' => 'status', 'v' => 'False' },
      m7: { 'cCI' => 'M0007', 'n' => 'status', 'v' => /^True(,True)*$/ },
      m11: { 'cCI' => 'M0011', 'n' => 'status', 'v' => /^False(,False)*$/ }
    }
  end
  let(:ok) do
    {
      m5: { 'cCI' => 'M0005', 'n' => 'status', 'v' => 'False' },
      m7: { 'cCI' => 'M0007', 'n' => 'status', 'v' => 'True' },
      m11: { 'cCI' => 'M0011', 'n' => 'status', 'v' => 'False' }
    }
  end
  let(:reject) do
    {
      m5: { 'cCI' => 'M0005', 'n' => 'status', 'v' => 'True' },
      m7: { 'cCI' => 'M0007', 'n' => 'status', 'v' => 'False' },
      m11: { 'cCI' => 'M0011', 'n' => 'status', 'v' => 'True' }
    }
  end

  def build_command_response(command_list)
    clock = RSMP::Clock.new
    RSMP::CommandResponse.new(
      'cId' => 'C1',
      'cTs' => clock.to_s,
      'rvs' => [command_list].flatten
    )
  end

  with '#collect' do
    it 'completes with a single command response' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
      expect(collector.summary).to be == [false, false, false]
      expect(collector.done?).to be == false
      collector.start
      collector.receive build_command_response(ok.values)
      expect(collector.summary).to be == [true, true, true]
      expect(collector.done?).to be == true
    end

    it 'completes with sequential command responses' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
      expect(collector.summary).to be == [false, false, false]
      expect(collector.done?).to be == false

      collector.start
      collector.receive build_command_response(ok[:m5])
      expect(collector.summary).to be == [true, false, false]
      expect(collector.done?).to be == false

      collector.receive build_command_response(ok[:m7])
      expect(collector.summary).to be == [true, true, false]
      expect(collector.done?).to be == false

      collector.receive build_command_response(ok[:m11])
      expect(collector.summary).to be == [true, true, true]
      expect(collector.done?).to be == true
    end

    it 'cannot mark matchers as not done' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
      expect(collector.done?).to be == false
      expect(collector.summary).to be == [false, false, false]

      collector.start
      collector.receive build_command_response(ok[:m5])
      expect(collector.summary).to be == [true, false, false]
      expect(collector.done?).to be == false

      collector.receive build_command_response(ok[:m7])
      expect(collector.summary).to be == [true, true, false]
      expect(collector.done?).to be == false

      collector.receive build_command_response(reject[:m5]) # try to clear m5
      expect(collector.summary).to be == [false, true, false]
      expect(collector.done?).to be == false
    end

    it 'raises if notified after being complete' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
      collector.start
      collector.receive build_command_response(ok.values)
      expect(collector.done?).to be == true
      expect { collector.receive build_command_response(ok.values) }.to raise_exception(RuntimeError)
    end

    it 'extra command responses are ignored' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
      collector.use_task task
      # proxy should have no receivers initially
      expect(proxy.receivers.size).to be == 0

      # start collection
      collect_task = task.async do
        collector.collect
      end

      # collector should have inserted itself as a receiver on the proxy
      expect(proxy.receivers.size).to be == 1
      expect(collector.done?).to be == false

      # send required values
      proxy.distribute build_command_response(ok.values)

      # should be done, and should have removed itself as a receiver
      expect(collector.done?).to be == true
      expect(proxy.receivers.size).to be == 0

      # additional messages should not reach the collector, and should not affect the result
      proxy.distribute build_command_response(reject.values)
      expect(collector.done?).to be == true
      collect_task.wait
    end
  end

  with '#collect with block' do
    it 'gets message and each item' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, task: task, timeout: collect_timeout)
      collect_task = task.async do
        messages = []
        items = []
        result = collector.collect do |message, item|
          if message
            messages << message
          elsif item
            items << item
          end
          nil
        end
        expect(result).to be == :ok
        expect(messages.size).to be == 1
        expect(items.size).to be == 3
        expect(collector.messages.size).to be == 1
      end
      collector.receive build_command_response([ok[:m5], ok[:m7], ok[:m11]])
      collect_task.wait
    end

    it 'can keep or reject items' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      my_want = { 'sCI' => 'S0001', 'n' => 'status' }
      collector = subject.new(proxy, [my_want], task: task, timeout: collect_timeout)
      collect_task = task.async do
        items = []
        result = collector.collect do |_message, item|
          next unless item

          items << item
          item['s'] == '3'
        end
        expect(result).to be == :ok
        expect(items.size).to be == 3
        expect(collector.messages.size).to be == 1
      end
      collector.receive build_command_response([my_want.merge('s' => '1')])
      collector.receive build_command_response([my_want.merge('s' => '2')])
      collector.receive build_command_response([my_want.merge('s' => '3')])
      collect_task.wait
    end

    it 'can cancel' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, task: task)
      collect_task = task.async do
        result = collector.collect do |_message, _item|
          collector.cancel
        end
        expect(result).to be == :cancelled
        expect(collector.messages.size).to be == 0
      end
      collector.receive build_command_response([ok[:m5], ok[:m7], ok[:m11]])
      collect_task.wait
    end

    it 'can cancel on MessageNotAck' do
      task = Async::Task.current
      m_id = RSMP::Message.make_m_id
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new proxy, want.values, m_id: m_id, timeout: collect_timeout
      collector.start
      expect(collector.status).to be == :collecting
      proxy.distribute RSMP::MessageNotAck.new('oMId' => m_id)
      expect(collector.status).to be == :cancelled
    end
  end
end
