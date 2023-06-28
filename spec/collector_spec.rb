RSpec.describe RSMP::Collector do
  let(:timeout) { 1 }

  describe '#collect' do
    it 'gets anything' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          result = collector.collect

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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, type: "Watchdog", num: 1, timeout: timeout
          result = collector.collect

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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, type: "Watchdog", num: 2, timeout: timeout
          result = collector.collect

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

    it 'gets a MessageAck' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, type: "MessageAck", num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::MessageAck)
        end
        proxy.notify RSMP::MessageAck.new
        collect_task.wait
      end
    end

    it 'gets a MessageNotAck' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, type: "MessageNotAck", num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::MessageNotAck)
        end
        proxy.notify RSMP::MessageNotAck.new
        collect_task.wait
      end
    end

    it 'gets a MessageAck from m_id' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        m_id = '397786b1-c8d0-4888-a557-241ad5772983'
        other_m_id = '297d122e-a2fb-4a22-a407-52b8c5133771'
        collect_task = task.async do
          collector = RSMP::AckCollector.new proxy, m_id: m_id, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::MessageAck)
          expect(collector.messages.first.attributes['oMId']).to eq(m_id)
        end
        proxy.notify RSMP::MessageAck.new "oMId" => other_m_id    # should be ignored because oMId does not match
        proxy.notify RSMP::MessageAck.new "oMId" => m_id          # should be collected, because oMID matches
        collect_task.wait
      end
    end

    it 'times out if nothing is received' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collector = RSMP::Collector.new proxy, type: "Watchdog", num: 1, timeout: timeout
        result = collector.collect

        expect(result).to eq(:timeout)
        expect(collector.messages).to be_an(Array)
        expect(collector.messages.size).to eq(0)
      end
    end

    it 'can be called with no timeout' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1
          result = collector.collect
          expect(result).to eq(:ok)
        end
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can filter by component id' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: 1, component: 'good'
          result = collector.collect

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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collector = RSMP::Collector.new proxy, task: task
        expect { collector.collect }.to raise_error(ArgumentError)
      end
    end

    it 'can cancel on MessageNotAck' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        message = RSMP::StatusRequest.new
        collect_task = task.async do
          collector = RSMP::Collector.new(
            proxy,
            type: "StatusUpdate",
            num: 1,
            timeout: timeout,
            m_id: message.m_id # id of original request. NotAck with matching mOId should cancel collection
          )
          result = collector.collect

          expect(result).to eq(:cancelled)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(0)
          expect(collector.error).to be_a(RSMP::MessageRejected )
        end
        proxy.notify RSMP::MessageNotAck.new 'oMId' => message.m_id
        collect_task.wait
      end
    end
  end

  describe '#collect with block' do
    it 'can keep or skip messages' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          messages = []
          result = collector.collect do |message|
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          result = collector.collect do |message|
            collector.cancel
          end
          expect(result).to eq(:cancelled)
          expect(collector.messages.size).to eq(0)
        end
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can cancel on schema error' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:cancelled)
          expect(collector.error).to be_a(RSMP::SchemaError)
          expect(collector.messages.size).to eq(0)
        end
        proxy.distribute_error RSMP::SchemaError.new, message: RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can cancel if disconnect' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout, cancel: {disconnect: true}
          result = collector.collect

          expect(result).to eq(:cancelled)
          expect(collector.error).to be_a(RSMP::DisconnectError)
          expect(collector.messages.size).to eq(0)
        end
        proxy.distribute_error RSMP::DisconnectError.new, message: RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'can be used without num or timeout' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, task: task
          messages = []
          result = collector.collect do |message|
            messages << message
            collector.cancel if messages.size >= 2
          end
          expect(result).to eq(:cancelled)
          expect(messages.size).to eq(2)
          expect(collector.messages.size).to eq(0)
        end
        proxy.notify RSMP::Watchdog.new
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end
  end

  describe "#collect!" do
    it "raises exception if not successful" do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          expect { collector.collect! }.to raise_error(RSMP::TimeoutError)
        end
        collect_task.wait
      end
    end

    it "returns messages if successful" do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
          messages = collector.collect!
          expect(messages).to be_an(Array)
          expect(messages.size).to eq(1)
          expect(messages.first).to be_an(RSMP::Watchdog)
        end
        proxy.notify RSMP::Watchdog.new
        collect_task.wait
      end
    end

    it 'raises on MessageNotAck' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        message = RSMP::StatusRequest.new
        collect_task = task.async do
          collector = RSMP::Collector.new(
            proxy,
            type: "StatusUpdate",
            num: 1,
            timeout: timeout,
            m_id: message.m_id # id of original request. NotAck with matching mOId should cancel collection
          )
          expect { collector.collect! }.to raise_error(RSMP::MessageRejected)

        end
        proxy.notify RSMP::MessageNotAck.new 'oMId' => message.m_id
        collect_task.wait
      end
    end
  end

  describe "#start" do
    it "sets status and returns immediately" do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        expect(collector.status).to eq(:collecting)
      end
    end
  end

  describe "#wait" do
    it "returns :ok if already complete" do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        proxy.notify RSMP::Watchdog.new
        expect(collector.messages.size).to eq(1)
        expect(collector.status).to eq(:ok)
        expect(collector.wait).to eq(:ok)
      end
    end

    it "returns :ok after completion" do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        collect_task = task.async do
          collector.wait
        end
        proxy.notify RSMP::Watchdog.new
        expect(collect_task.wait).to eq(:ok)
        expect(collector.messages.size).to eq(1)
        expect(collector.status).to eq(:ok)
      end
    end

    it "returns :timeout" do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        expect(collector.wait).to eq(:timeout)
      end
    end
  end

  describe "#wait!" do
    it "returns messages if already complete" do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        proxy.notify RSMP::Watchdog.new
        expect(collector.messages.size).to eq(1)
        messages = collector.wait!
        expect(messages).to be_an(Array)
        expect(messages.size).to eq(1)
        expect(messages.first).to be_an(RSMP::Watchdog)
      end
    end

    it "returns messages after completion" do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        collect_task = task.async do
          collector.wait!
        end
        proxy.notify RSMP::Watchdog.new
        messages = collect_task.wait
        expect(messages).to be_an(Array)
        expect(messages.size).to eq(1)
        expect(messages.first).to be_an(RSMP::Watchdog)
      end
    end

    it "raises TimeoutError" do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collector = RSMP::Collector.new proxy, num: 1, timeout: timeout
        collector.start
        expect { collector.wait! }.to raise_error(RSMP::TimeoutError)
      end
    end
  end
end
