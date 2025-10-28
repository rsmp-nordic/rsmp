include RSMP

RSpec.describe StatusCollector do
  let(:timeout) { 0.01 }
  let(:want) do
    {
      s5: { 'sCI' => 'S0005', 'n' => 'status', 's' => 'False' },
      s7: { 'sCI' => 'S0007', 'n' => 'status', 's' => /^True(,True)*$/ },
      s11: { 'sCI' => 'S0011', 'n' => 'status', 's' => /^False(,False)*$/ }
    }
  end
  let(:ok) do
    {
      s5: { 'sCI' => 'S0005', 'n' => 'status', 's' => 'False' },
      s7: { 'sCI' => 'S0007', 'n' => 'status', 's' => 'True' },
      s11: { 'sCI' => 'S0011', 'n' => 'status', 's' => 'False' }
    }
  end
  let(:reject) do
    {
      s5: { 'sCI' => 'S0005', 'n' => 'status', 's' => 'True' },
      s7: { 'sCI' => 'S0007', 'n' => 'status', 's' => 'False' },
      s11: { 'sCI' => 'S0011', 'n' => 'status', 's' => 'True' }
    }
  end

  def build_status_message(status_list)
    clock = Clock.new
    RSMP::StatusUpdate.new(
      'cId' => 'C1',
      'sTs' => clock.to_s,
      'sS' => [status_list].flatten
    )
  end

  describe '#collect' do
    it 'completes with a single status update' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, timeout: timeout)
        expect(collector.summary).to eq([false, false, false])
        expect(collector.done?).to be(false)

        collector.start
        collector.receive build_status_message(ok.values)
        expect(collector.summary).to eq([true, true, true])
        expect(collector.done?).to be(true)
      end
    end

    it 'completes with sequential status updates' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, timeout: timeout)
        expect(collector.summary).to eq([false, false, false])
        expect(collector.done?).to be(false)

        collector.start
        collector.receive build_status_message(ok[:s5])
        expect(collector.summary).to eq([true, false, false])
        expect(collector.done?).to be(false)

        collector.receive build_status_message(ok[:s7])
        expect(collector.summary).to eq([true, true, false])
        expect(collector.done?).to be(false)

        collector.receive build_status_message(ok[:s11])
        expect(collector.summary).to eq([true, true, true])
        expect(collector.done?).to be(true)
      end
    end

    it 'marks matchers as not done' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, timeout: timeout)
        expect(collector.done?).to be(false)
        expect(collector.summary).to eq([false, false, false])

        collector.start
        collector.receive build_status_message(ok[:s5]) # set s5
        expect(collector.summary).to eq([true, false, false])
        expect(collector.done?).to be(false)

        collector.receive build_status_message(ok[:s7])
        expect(collector.summary).to eq([true, true, false])
        expect(collector.done?).to be(false)

        collector.receive build_status_message(reject[:s5]) # clear s5
        expect(collector.summary).to eq([false, true, false])
        expect(collector.done?).to be(false)

        collector.receive build_status_message(ok[:s11])
        expect(collector.summary).to eq([false, true, true])
        expect(collector.done?).to be(false)

        collector.receive build_status_message(ok[:s5]) # set s5 againt
        expect(collector.summary).to eq([true, true, true])
        expect(collector.done?).to be(true)
      end
    end

    it 'raises if notified after being complete' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, timeout: timeout)
        collector.start
        collector.receive build_status_message(ok.values)
        expect(collector.done?).to be(true)
        expect { collector.receive build_status_message(ok.values) }.to raise_error(RuntimeError)
      end
    end

    it 'extra status updates are ignored' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, timeout: timeout)
        collector.use_task task
        # proxy should have no receivers initially
        expect(proxy.receivers.size).to eq(0)

        # start collection
        task.async do
          collector.collect
        end

        # collector should have inserted inself as a receiver on the proxy
        expect(proxy.receivers.size).to eq(1)
        expect(collector.done?).to be(false)

        # send required values
        proxy.distribute build_status_message(ok.values)

        # should be done, and should have rmeoved itself as a receiver
        expect(collector.done?).to be(true)
        expect(proxy.receivers.size).to eq(0)

        # additional messages should there not reach the collector, and should not affect the result
        proxy.distribute build_status_message(reject.values)
        expect(collector.done?).to be(true)
      end
    end
  end

  describe '#collect with block' do
    it 'gets message and each item' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, task: task, timeout: timeout)
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
          expect(result).to eq(:ok)
          expect(messages.size).to eq(1)
          expect(items.size).to eq(3)
          expect(collector.messages.size).to eq(1)
        end
        collector.receive build_status_message([ok[:s5], ok[:s7], ok[:s11]])  # one message with 3 items
        collect_task.wait
      end
    end

    it 'can keep or reject items' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        want = { 'sCI' => 'S0001', 'n' => 'status' }
        collector = described_class.new(proxy, [want], task: task, timeout: timeout)
        collect_task = task.async do
          items = []
          result = collector.collect do |_message, item|
            next unless item

            items << item
            item['s'] == '3'
          end
          expect(result).to eq(:ok)
          expect(items.size).to eq(3)
          expect(collector.messages.size).to eq(1)
        end
        collector.receive build_status_message([want.merge('s' => '1')])
        collector.receive build_status_message([want.merge('s' => '2')])
        collector.receive build_status_message([want.merge('s' => '3')])
        collect_task.wait
      end
    end

    it 'can cancel' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, task: task)
        collect_task = task.async do
          result = collector.collect do |_message, _item|
            collector.cancel
          end
          expect(result).to eq(:cancelled)
          expect(collector.messages.size).to eq(0)
        end
        collector.receive build_status_message([ok[:s5], ok[:s7], ok[:s11]])  # one message with 3 items
        collect_task.wait
      end
    end
  end
end
