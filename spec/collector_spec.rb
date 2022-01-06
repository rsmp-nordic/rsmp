RSpec.describe RSMP::Collector do
  let(:timeout) { 0.001 }

  describe '#collect' do
    it 'gets anything' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { num: 1, timeout: timeout }
          collector = RSMP::Collector.new site_proxy
          result = collector.collect task, options

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::Watchdog)
        end
        site_proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'gets one Watchdog' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { type: "Watchdog", num: 1, timeout: timeout }
          collector = RSMP::Collector.new site_proxy
          result = collector.collect task, options

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::Watchdog)
        end
        site_proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'gets two Watchdogs' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { type: "Watchdog", num: 2, timeout: timeout }
          collector = RSMP::Collector.new site_proxy
          result = collector.collect task, options

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(2)
          expect(collector.messages.first).to be_an(RSMP::Watchdog)
          expect(collector.messages.last).to be_an(RSMP::Watchdog)
        end
        site_proxy.notify RSMP::Watchdog.new
        site_proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'times out if nothing is received' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { type: "Watchdog", num: 1, timeout: timeout }
          collector = RSMP::Collector.new site_proxy
          result = collector.collect task, options

          expect(result).to eq(:timeout)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(0)
        end
        collect_task.wait
      end
    end

    it 'can be called with no timeout' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          collector = RSMP::Collector.new site_proxy, num: 1
          result = collector.collect task
          expect(result).to eq(:ok)
        end
        site_proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can filter by component id' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { num: 1, timeout: 1, component: 'good' }
          collector = RSMP::Collector.new site_proxy
          result = collector.collect task, options

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::StatusUpdate)
        end
        site_proxy.notify RSMP::StatusUpdate.new(cId: 'bad')    # should be ignored
        site_proxy.notify RSMP::StatusUpdate.new(cId: 'good')   # should be kept
        collect_task.wait
      end
    end

    it 'raises if required options are missing' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
          collector = RSMP::Collector.new site_proxy
        expect { collector.collect task }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#collect with block' do
    it 'can keep or skip messages' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { num: 1, timeout: timeout }
          collector = RSMP::Collector.new site_proxy
          messages = []
          result = collector.collect task, options do |message|
            messages << message
            :keep if message.is_a? RSMP::AggregatedStatus
          end
          expect(result).to eq(:ok)
          expect(messages.size).to eq(2)
          expect(collector.messages.size).to eq(1)
        end
        site_proxy.notify RSMP::Watchdog.new
        site_proxy.notify RSMP::AggregatedStatus.new
        collect_task.wait
      end
    end

    it 'can cancel collection' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { num: 1, timeout: timeout }
          collector = RSMP::Collector.new site_proxy
          result = collector.collect task, options do |message|
            :cancel
          end
          expect(result).to eq(:cancelled)
          expect(collector.messages.size).to eq(0)
        end
        site_proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can cancel on schema error' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { num: 1, timeout: timeout }
          collector = RSMP::Collector.new site_proxy
          result = collector.collect task, options

          expect(result).to eq(:cancelled)
          expect(collector.error).to be_a(RSMP::SchemaError)
          expect(collector.messages.size).to eq(0)
        end
        site_proxy.distribute_error RSMP::SchemaError.new, message: RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can cancel if disconnect' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { num: 1, timeout: timeout, cancel: {disconnect: true} }
          collector = RSMP::Collector.new site_proxy
          result = collector.collect task, options

          expect(result).to eq(:cancelled)
          expect(collector.error).to be_a(RSMP::DisconnectError)
          expect(collector.messages.size).to eq(0)
        end
        site_proxy.distribute_error RSMP::DisconnectError.new, message: RSMP::Watchdog.new
        collect_task.wait
      end
    end
  end

  describe "#collect!" do
    it "raises exception if not successful" do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { num: 1, timeout: timeout }
          collector = RSMP::Collector.new site_proxy, options
          expect { collector.collect! task }.to raise_error(RSMP::TimeoutError)
        end
        collect_task.wait
      end
    end

    it "returns messages if successful" do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = { num: 1, timeout: timeout }
          collector = RSMP::Collector.new site_proxy, options
          messages = collector.collect! task
          expect(messages).to be_an(Array)
          expect(messages.size).to eq(1)
          expect(messages.first).to be_an(RSMP::Watchdog)
        end
        site_proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end
  end
end
