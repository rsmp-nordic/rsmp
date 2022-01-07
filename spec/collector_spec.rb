RSpec.describe RSMP::Collector do
  let(:timeout) { 0.001 }

  describe '#collect' do
    it 'gets anything' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          result = collector.collect task

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::Watchdog)
        end
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'gets one Watchdog' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, type: "Watchdog", num: 1, timeout: timeout
          result = collector.collect task

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::Watchdog)
        end
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'gets two Watchdogs' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, type: "Watchdog", num: 2, timeout: timeout
          result = collector.collect task

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(2)
          expect(collector.messages.first).to be_an(RSMP::Watchdog)
          expect(collector.messages.last).to be_an(RSMP::Watchdog)
        end
        proxy.notify RSMP::Watchdog.new
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'times out if nothing is received' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = RSMP::Collector.new proxy, type: "Watchdog", num: 1, timeout: timeout
        result = collector.collect task

        expect(result).to eq(:timeout)
        expect(collector.messages).to be_an(Array)
        expect(collector.messages.size).to eq(0)
      end
    end

    it 'can be called with no timeout' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1
          result = collector.collect task
          expect(result).to eq(:ok)
        end
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can filter by component id' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: 1, component: 'good'
          result = collector.collect task

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::StatusUpdate)
        end
        proxy.notify RSMP::StatusUpdate.new(cId: 'bad')    # should be ignored
        proxy.notify RSMP::StatusUpdate.new(cId: 'good')   # should be kept
        collect_task.wait
      end
    end

    it 'raises if required options are missing' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = RSMP::Collector.new proxy
        expect { collector.collect task }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#collect with block' do
    it 'can keep or skip messages' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          messages = []
          result = collector.collect task do |message|
            messages << message
            :keep if message.is_a? RSMP::AggregatedStatus
          end
          expect(result).to eq(:ok)
          expect(messages.size).to eq(2)
          expect(collector.messages.size).to eq(1)
        end
        proxy.notify RSMP::Watchdog.new
        proxy.notify RSMP::AggregatedStatus.new
        collect_task.wait
      end
    end

    it 'can cancel collection' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          result = collector.collect task do |message|
            :cancel
          end
          expect(result).to eq(:cancelled)
          expect(collector.messages.size).to eq(0)
        end
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can cancel on schema error' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          result = collector.collect task

          expect(result).to eq(:cancelled)
          expect(collector.error).to be_a(RSMP::SchemaError)
          expect(collector.messages.size).to eq(0)
        end
        proxy.distribute_error RSMP::SchemaError.new, message: RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can cancel if disconnect' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout, cancel: {disconnect: true}
          result = collector.collect task

          expect(result).to eq(:cancelled)
          expect(collector.error).to be_a(RSMP::DisconnectError)
          expect(collector.messages.size).to eq(0)
        end
        proxy.distribute_error RSMP::DisconnectError.new, message: RSMP::Watchdog.new
        collect_task.wait
      end
    end
  end

  describe "#collect!" do
    it "raises exception if not successful" do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          expect { collector.collect! task }.to raise_error(RSMP::TimeoutError)
        end
        collect_task.wait
      end
    end

    it "returns messages if successful" do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          messages = collector.collect! task
          expect(messages).to be_an(Array)
          expect(messages.size).to eq(1)
          expect(messages.first).to be_an(RSMP::Watchdog)
        end
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end
  end

  describe "#start" do
    it "sets status and returns immediately" do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        expect(collector.status).to eq(:collecting)
      end
    end
  end

  describe "#wait" do
    it "returns :ok if already complete" do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        proxy.notify RSMP::Watchdog.new
        expect(collector.messages.size).to eq(1)
        expect(collector.status).to eq(:ok)
        expect(collector.wait task).to eq(:ok)
      end
    end

    it "returns :ok after completion" do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        collect_task = task.async do
          collector.wait task
        end
        proxy.notify RSMP::Watchdog.new
        expect(collect_task.wait).to eq(:ok)
        expect(collector.messages.size).to eq(1)
        expect(collector.status).to eq(:ok)
      end
    end

    it "returns :timeout" do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        expect(collector.wait task).to eq(:timeout)
      end
    end
  end
  
  describe "#wait!" do
    it "returns :ok if already complete" do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        proxy.notify RSMP::Watchdog.new
        expect(collector.messages.size).to eq(1)
        expect(collector.wait! task).to eq(:ok)
      end
    end

    it "returns :ok after completion" do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        collect_task = task.async do
          collector.wait! task
        end
        proxy.notify RSMP::Watchdog.new
        expect(collect_task.wait).to eq(:ok)
        expect(collector.messages.size).to eq(1)
        expect(collector.status).to eq(:ok)
      end
    end

    it "raises TimeoutError" do
      RSMP::SiteProxyStub.async do |task,proxy|
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        expect { collector.wait! task }.to raise_error(RSMP::TimeoutError)
      end
    end
  end
end
