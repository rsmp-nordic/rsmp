describe RSMP::StatusCollector do
  let(:collect_timeout) { 0.01 }
  let(:want) do
    {
      s5: { 'sCI' => 'S0005', 'n' => 'status', 's' => false },
      s7: { 'sCI' => 'S0007', 'n' => 'status', 's' => [true] },
      s11: { 'sCI' => 'S0011', 'n' => 'status', 's' => [false] }
    }
  end
  let(:ok) do
    {
      s5: { 'sCI' => 'S0005', 'n' => 'status', 's' => false },
      s7: { 'sCI' => 'S0007', 'n' => 'status', 's' => [true] },
      s11: { 'sCI' => 'S0011', 'n' => 'status', 's' => [false] }
    }
  end
  let(:reject) do
    {
      s5: { 'sCI' => 'S0005', 'n' => 'status', 's' => true },
      s7: { 'sCI' => 'S0007', 'n' => 'status', 's' => [false] },
      s11: { 'sCI' => 'S0011', 'n' => 'status', 's' => [true] }
    }
  end

  def build_status_message(status_list)
    clock = RSMP::Clock.new
    RSMP::StatusUpdate.new(
      'cId' => 'C1',
      'sTs' => clock.to_s,
      'sS' => [status_list].flatten
    )
  end

  with '#collect' do
    it 'completes with a single status update' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
      expect(collector.summary).to be == [false, false, false]
      expect(collector.done?).to be == false

      collector.start
      collector.receive build_status_message(ok.values)
      expect(collector.summary).to be == [true, true, true]
      expect(collector.done?).to be == true
    end

    it 'completes with sequential status updates' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
      expect(collector.summary).to be == [false, false, false]
      expect(collector.done?).to be == false

      collector.start
      collector.receive build_status_message(ok[:s5])
      expect(collector.summary).to be == [true, false, false]
      expect(collector.done?).to be == false

      collector.receive build_status_message(ok[:s7])
      expect(collector.summary).to be == [true, true, false]
      expect(collector.done?).to be == false

      collector.receive build_status_message(ok[:s11])
      expect(collector.summary).to be == [true, true, true]
      expect(collector.done?).to be == true
    end

    it 'marks matchers as not done' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
      expect(collector.done?).to be == false
      expect(collector.summary).to be == [false, false, false]

      collector.start
      collector.receive build_status_message(ok[:s5])
      expect(collector.summary).to be == [true, false, false]
      expect(collector.done?).to be == false

      collector.receive build_status_message(ok[:s7])
      expect(collector.summary).to be == [true, true, false]
      expect(collector.done?).to be == false

      collector.receive build_status_message(reject[:s5]) # clear s5
      expect(collector.summary).to be == [false, true, false]
      expect(collector.done?).to be == false

      collector.receive build_status_message(ok[:s11])
      expect(collector.summary).to be == [false, true, true]
      expect(collector.done?).to be == false

      collector.receive build_status_message(ok[:s5]) # set s5 again
      expect(collector.summary).to be == [true, true, true]
      expect(collector.done?).to be == true
    end

    it 'ignores notifications after being complete' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
      collector.start
      collector.receive build_status_message(ok.values)
      expect(collector.done?).to be == true
      expect(collector.receive(build_status_message(ok.values))).to be_nil
    end

    it 'extra status updates are ignored' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
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
      proxy.distribute build_status_message(ok.values)

      # should be done, and should have removed itself as a receiver
      expect(collector.done?).to be == true
      expect(proxy.receivers.size).to be == 0

      # additional messages should not reach the collector, and should not affect the result
      proxy.distribute build_status_message(reject.values)
      expect(collector.done?).to be == true
      collect_task.wait
    end
  end

  with 'message predicate' do
    it 'ignores fresh updates until matching statuses arrive within the timestamp window' do
      proxy = RSMP::SiteProxyStub.new Async::Task.current
      window = Time.utc(2026, 1, 1, 12, 0, 1)...Time.utc(2026, 1, 1, 12, 0, 5)
      seen = []
      predicate = proc do |message|
        seen << message
        window.cover?(Time.parse(message.attribute('sTs')))
      end
      collector = subject.new(proxy, want.values, predicate: predicate, timeout: collect_timeout)
      collector.start

      fresh = build_status_message(ok.values)
      fresh.attributes['sTs'] = '2026-01-01T12:00:05.000Z'
      proxy.distribute fresh
      expect(collector.summary).to be == [false, false, false]
      expect(collector.active?).to be == true

      buffered = build_status_message(ok.values)
      buffered.attributes['sTs'] = '2026-01-01T12:00:02.000Z'
      proxy.distribute buffered
      expect(collector.wait!).to be == [buffered]
      expect(seen).to be == [fresh, buffered]
    end

    it 'does not clear earlier item matches when the predicate rejects a message' do
      proxy = RSMP::SiteProxyStub.new Async::Task.current
      predicate = ->(message) { message.attribute('cId') == 'C1' }
      collector = subject.new(proxy, want.values, predicate: predicate, timeout: collect_timeout)
      collector.start
      first = build_status_message(ok[:s5])
      proxy.distribute first

      rejected = build_status_message(reject[:s5])
      rejected.attributes['cId'] = 'C2'
      proxy.distribute rejected
      expect(collector.summary).to be == [true, false, false]

      remaining = build_status_message([ok[:s7], ok[:s11]])
      proxy.distribute remaining
      expect(collector.wait!).to be == [first, remaining]
    end
  end

  with '#collect with block' do
    it 'gets message and each item' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values, timeout: collect_timeout)
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
        expect(result.success?).to be == true
        expect(messages.size).to be == 1
        expect(items.size).to be == 3
        expect(collector.messages.size).to be == 1
      end
      collector.receive build_status_message([ok[:s5], ok[:s7], ok[:s11]])
      collect_task.wait
    end

    it 'can keep or reject items' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      my_want = { 'sCI' => 'S0001', 'n' => 'status' }
      collector = subject.new(proxy, [my_want], timeout: collect_timeout)
      collect_task = task.async do
        items = []
        result = collector.collect do |_message, item|
          next unless item

          items << item
          item['s'] == '3'
        end
        expect(result.success?).to be == true
        expect(items.size).to be == 3
        expect(collector.messages.size).to be == 1
      end
      collector.receive build_status_message([my_want.merge('s' => '1')])
      collector.receive build_status_message([my_want.merge('s' => '2')])
      collector.receive build_status_message([my_want.merge('s' => '3')])
      collect_task.wait
    end

    it 'can cancel' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new(proxy, want.values)
      collect_task = task.async do
        result = collector.collect do |_message, _item|
          collector.cancel
        end
        expect(result.failure?).to be == true
        expect(result.failure.code).to be == :cancelled
        expect(collector.messages.size).to be == 0
      end
      collector.receive build_status_message([ok[:s5], ok[:s7], ok[:s11]])
      collect_task.wait
    end
  end
end
