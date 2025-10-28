RSpec.describe RSMP::CommandResponseCollector do
  let(:timeout) { 0.01 }
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

  def build_command_reponse(command_list)
    clock = RSMP::Clock.new
    RSMP::CommandResponse.new(
      'cId' => 'C1',
      'cTs' => clock.to_s,
      'rvs' => [command_list].flatten
    )
  end

  describe '#collect' do
    it 'completes with a single command response' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, timeout: timeout)
        expect(collector.summary).to eq([false, false, false])
        expect(collector.done?).to be(false)
        collector.start
        collector.receive build_command_reponse(ok.values)
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
        collector.receive build_command_reponse(ok[:m5])
        expect(collector.summary).to eq([true, false, false])
        expect(collector.done?).to be(false)

        collector.receive build_command_reponse(ok[:m7])
        expect(collector.summary).to eq([true, true, false])
        expect(collector.done?).to be(false)

        collector.receive build_command_reponse(ok[:m11])
        expect(collector.summary).to eq([true, true, true])
        expect(collector.done?).to be(true)
      end
    end

    it 'cannot marks matchers as not done' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, timeout: timeout)
        expect(collector.done?).to be(false)
        expect(collector.summary).to eq([false, false, false])

        collector.start
        collector.receive build_command_reponse(ok[:m5]) # set s5
        expect(collector.summary).to eq([true, false, false])
        expect(collector.done?).to be(false)

        collector.receive build_command_reponse(ok[:m7])
        expect(collector.summary).to eq([true, true, false])
        expect(collector.done?).to be(false)
        collector.receive build_command_reponse(reject[:m5]) # clear s5
        expect(collector.summary).to eq([false, true, false])
        expect(collector.done?).to be(false)
        # collector.receive build_command_reponse(ok[:m11])
        # expect(collector.summary).to eq([false,true,true])
        # expect(collector.done?).to be(false)
        # collector.receive build_command_reponse(ok[:m5])      # set s5 againt
        # expect(collector.summary).to eq([true,true,true])
        # expect(collector.done?).to be(true)
      end
    end

    it 'raises if notified after being complete' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new(proxy, want.values, timeout: timeout)
        collector.start
        collector.receive build_command_reponse(ok.values)
        expect(collector.done?).to be(true)
        expect { collector.receive build_command_reponse(ok.values) }.to raise_error(RuntimeError)
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
        proxy.distribute build_command_reponse(ok.values)

        # should be done, and should have remeoved itself as a receiver
        expect(collector.done?).to be(true)
        expect(proxy.receivers.size).to eq(0)

        # additional messages should not reach the collector, and should not affect the result
        proxy.distribute build_command_reponse(reject.values)
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
        collector.receive build_command_reponse([ok[:m5], ok[:m7], ok[:m11]])  # one message with 3 items
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
        collector.receive build_command_reponse([want.merge('s' => '1')])
        collector.receive build_command_reponse([want.merge('s' => '2')])
        collector.receive build_command_reponse([want.merge('s' => '3')])
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
        collector.receive build_command_reponse([ok[:m5], ok[:m7], ok[:m11]])  # one message with 3 items
        collect_task.wait
      end
    end

    it 'can cancel on MessageNotAck' do
      AsyncRSpec.async do |task|
        m_id = RSMP::Message.make_m_id
        proxy = RSMP::SiteProxyStub.new task
        collector = described_class.new proxy, want.values, m_id: m_id, timeout: timeout
        collector.start
        expect(collector.status).to eq(:collecting)
        proxy.distribute RSMP::MessageNotAck.new('oMId' => m_id)
        expect(collector.status).to eq(:cancelled)
      end
    end
  end
end
