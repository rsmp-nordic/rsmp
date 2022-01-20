include RSMP
RSpec.describe StatusCollector do
  let(:timeout) { 0.001 }

  def build_status_message status_list
    clock = Clock.new
    RSMP::StatusUpdate.new(
      "cId" => "C1",
      "sTs" => clock.to_s,
      "sS" => [status_list].flatten
    )
  end

  let(:want) {
    {
      s5: {"sCI" => "S0005","n" => "status","s" => "False"},
      s7: {"sCI" => "S0007","n" => "status","s" => /^True(,True)*$/},
      s11: {"sCI" => "S0011","n" => "status","s" => /^False(,False)*$/},
    }
  }

  let(:ok) {
    {
      s5: {"sCI" => "S0005","n" => "status","s" => "False"},
      s7: {"sCI" => "S0007","n" => "status","s" => "True"},
      s11: {"sCI" => "S0011","n" => "status","s" => "False"},
    }
  }

  let(:reject) {
    {
      s5: {"sCI" => "S0005","n" => "status","s" => "True"},
      s7: {"sCI" => "S0007","n" => "status","s" => "False"},
      s11: {"sCI" => "S0011","n" => "status","s" => "True"},
    }
  }

  describe "#collect" do

    it 'completes with a single status update' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = StatusCollector.new(proxy, want.values, timeout: timeout)
        expect(collector.summary).to eq([false,false,false])
        expect(collector.done?).to be(false)

        collector.start
        collector.notify build_status_message(ok.values)
        expect(collector.summary).to eq([true,true,true])
        expect(collector.done?).to be(true)
      end
    end

    it 'completes with sequential status updates' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = StatusCollector.new(proxy, want.values, timeout: timeout)
        expect(collector.summary).to eq([false,false,false])
        expect(collector.done?).to be(false)

        collector.start
        collector.notify build_status_message(ok[:s5])
        expect(collector.summary).to eq([true,false,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s7])
        expect(collector.summary).to eq([true,true,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s11])
        expect(collector.summary).to eq([true,true,true])
        expect(collector.done?).to be(true)
      end
    end

    it 'marks queries as not done' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = StatusCollector.new(proxy, want.values, timeout: timeout)
        expect(collector.done?).to be(false)
        expect(collector.summary).to eq([false,false,false])

        collector.start
        collector.notify build_status_message(ok[:s5])      # set s5
        expect(collector.summary).to eq([true,false,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s7])
        expect(collector.summary).to eq([true,true,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(reject[:s5])    # clear s5
        expect(collector.summary).to eq([false,true,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s11])
        expect(collector.summary).to eq([false,true,true])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s5])      # set s5 againt
        expect(collector.summary).to eq([true,true,true])
        expect(collector.done?).to be(true)
      end
    end

    it 'raises if notified after being complete' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = StatusCollector.new(proxy, want.values, timeout: timeout)
        collector.start
        collector.notify build_status_message(ok.values)
        expect(collector.done?).to be(true)
        expect { collector.notify build_status_message(ok.values) }.to raise_error(RuntimeError)
      end
    end

    it 'extra status updates are ignored' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = StatusCollector.new(proxy, want.values, timeout: timeout)
        collector.use_task task
        # proxy should have no listeners initially
        expect(proxy.listeners.size).to eq(0)

        # start collection
        collect_task = task.async do
          collector.collect
        end

        # collector should have inserted inself as a listener on the proxy
        expect(proxy.listeners.size).to eq(1)
        expect(collector.done?).to be(false)

        # send required values
        proxy.notify build_status_message(ok.values)

        # should be done, and should have rmeoved itself as a listener
        expect(collector.done?).to be(true)
        expect(proxy.listeners.size).to eq(0)

        # additional messages should there not reach the collector, and should not affect the result
        proxy.notify build_status_message(reject.values)
        expect(collector.done?).to be(true)
      end
    end
  end

  describe '#collect with block' do
    it 'gets message and each item' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = StatusCollector.new(proxy, want.values, task: task, timeout: timeout)
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
        collector.notify build_status_message([ok[:s5],ok[:s7],ok[:s11]])  # one message with 3 items
        collect_task.wait
      end
    end

    it 'can keep or reject items' do
      RSMP::SiteProxyStub.async do |task,proxy|
        want = {"sCI" => "S0001","n" => "status"}
        collector = StatusCollector.new(proxy, [want], task: task, timeout: timeout)
        collect_task = task.async do
          items = []
          result = collector.collect do |message, item|
            next unless item
            items << item
            item['s'] == '3'
          end
          expect(result).to eq(:ok)
          expect(items.size).to eq(3)
          expect(collector.messages.size).to eq(1)
        end
        collector.notify build_status_message([want.merge('s'=>'1')])
        collector.notify build_status_message([want.merge('s'=>'2')])
        collector.notify build_status_message([want.merge('s'=>'3')])
        collect_task.wait
      end
    end

    it 'can cancel' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = StatusCollector.new(proxy, want.values, task: task)
        collect_task = task.async do
          result = collector.collect do |message, item|
            collector.cancel
          end
          expect(result).to eq(:cancelled)
          expect(collector.messages.size).to eq(0)
        end
        collector.notify build_status_message([ok[:s5],ok[:s7],ok[:s11]])  # one message with 3 items
        collect_task.wait
      end
    end
  end
end
