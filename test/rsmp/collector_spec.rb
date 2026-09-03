require_relative '../support/site_proxy_stub'

describe RSMP::Collector do
  let(:collect_timeout) { 0.01 }

  with '#collect' do
    it 'gets anything' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result.success?).to be == true
        expect(result.value).to be_a(RSMP::Collection)
        expect(collector.messages).to be_a(Array)
        expect(collector.messages.size).to be == 1
        expect(collector.messages.first).to be_a(RSMP::Watchdog)
      end
      proxy.distribute RSMP::Watchdog.new
      collect_task.wait
    end

    it 'gets one Watchdog' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        filter = RSMP::Filter.new type: 'Watchdog'
        collector = subject.new proxy, filter: filter, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result.success?).to be == true
        expect(collector.messages).to be_a(Array)
        expect(collector.messages.size).to be == 1
        expect(collector.messages.first).to be_a(RSMP::Watchdog)
      end
      proxy.distribute RSMP::Watchdog.new
      collect_task.wait
    end

    it 'gets two Watchdogs' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        filter = RSMP::Filter.new type: 'Watchdog'
        collector = subject.new proxy, filter: filter, num: 2, timeout: collect_timeout
        result = collector.collect

        expect(result.success?).to be == true
        expect(collector.messages).to be_a(Array)
        expect(collector.messages.size).to be == 2
        expect(collector.messages.first).to be_a(RSMP::Watchdog)
        expect(collector.messages.last).to be_a(RSMP::Watchdog)
      end
      proxy.distribute RSMP::Watchdog.new
      proxy.distribute RSMP::Watchdog.new
      collect_task.wait
    end

    it 'gets a MessageAck' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        filter = RSMP::Filter.new type: 'MessageAck'
        collector = subject.new proxy, filter: filter, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result.success?).to be == true
        expect(collector.messages).to be_a(Array)
        expect(collector.messages.size).to be == 1
        expect(collector.messages.first).to be_a(RSMP::MessageAck)
      end
      proxy.distribute RSMP::MessageAck.new
      collect_task.wait
    end

    it 'gets a MessageAck from m_id' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      m_id = '397786b1-c8d0-4888-a557-241ad5772983'
      other_m_id = '297d122e-a2fb-4a22-a407-52b8c5133771'
      collect_task = task.async do
        collector = RSMP::AckCollector.new proxy, m_id: m_id, timeout: collect_timeout
        result = collector.collect

        expect(result.success?).to be == true
        expect(collector.messages).to be_a(Array)
        expect(collector.messages.size).to be == 1
        expect(collector.messages.first).to be_a(RSMP::MessageAck)
        expect(collector.messages.first.attributes['oMId']).to be == m_id
      end
      proxy.distribute RSMP::MessageAck.new 'oMId' => other_m_id
      proxy.distribute RSMP::MessageAck.new 'oMId' => m_id
      collect_task.wait
    end

    it 'gets a MessageNotAck' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        filter = RSMP::Filter.new type: 'MessageNotAck'
        collector = subject.new proxy, filter: filter, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result.success?).to be == true
        expect(collector.messages).to be_a(Array)
        expect(collector.messages.size).to be == 1
        expect(collector.messages.first).to be_a(RSMP::MessageNotAck)
      end
      proxy.distribute RSMP::MessageNotAck.new
      collect_task.wait
    end

    it 'times out if nothing is received' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      filter = RSMP::Filter.new type: 'Watchdog'
      collector = subject.new proxy, filter: filter, num: 1, timeout: collect_timeout
      result = collector.collect

      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :timeout
      expect(collector.messages).to be_a(Array)
      expect(collector.messages.size).to be == 0
    end

    it 'can be called with no timeout' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1
        result = collector.collect
        expect(result.success?).to be == true
      end
      proxy.distribute RSMP::Watchdog.new
      collect_task.wait
    end

    it 'can filter by component id' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        filter = RSMP::Filter.new component: 'good'
        collector = subject.new proxy, num: 1, timeout: 1, filter: filter
        result = collector.collect

        expect(result.success?).to be == true
        expect(collector.messages).to be_a(Array)
        expect(collector.messages.size).to be == 1
        expect(collector.messages.first).to be_a(RSMP::StatusUpdate)
      end
      proxy.distribute RSMP::StatusUpdate.new(cId: 'bad')
      proxy.distribute RSMP::StatusUpdate.new(cId: 'good')
      collect_task.wait
    end

    it 'raises if required options are missing' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new proxy
      expect { collector.collect }.to raise_exception(ArgumentError)
    end

    it 'can cancel on MessageNotAck' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      message = RSMP::StatusRequest.new
      collect_task = task.async do
        filter = RSMP::Filter.new type: 'StatusUpdate'
        collector = subject.new(
          proxy,
          filter: filter,
          num: 1,
          timeout: collect_timeout,
          m_id: message.m_id
        )
        result = collector.collect

        expect(result.failure?).to be == true
        expect(result.failure.code).to be == :message_rejected
        expect(collector.messages).to be_a(Array)
        expect(collector.messages.size).to be == 0
        expect(result.failure.context[:message]).to be_a(RSMP::MessageNotAck)
      end
      proxy.distribute RSMP::MessageNotAck.new 'oMId' => message.m_id
      collect_task.wait
    end
  end

  with '#collect with block' do
    it 'can keep or skip messages' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout
        messages = []
        result = collector.collect do |message|
          messages << message
          :keep if message.is_a? RSMP::AggregatedStatus
        end
        expect(result.success?).to be == true
        expect(messages.size).to be == 2
        expect(collector.messages.size).to be == 1
      end
      proxy.distribute RSMP::Watchdog.new
      proxy.distribute RSMP::AggregatedStatus.new
      collect_task.wait
    end

    it 'can cancel collection' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout
        result = collector.collect do |_message|
          collector.cancel
        end
        expect(result.failure?).to be == true
        expect(result.failure.code).to be == :cancelled
        expect(collector.messages.size).to be == 0
      end
      proxy.distribute RSMP::Watchdog.new
      collect_task.wait
    end

    it 'can cancel on schema error' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result.failure?).to be == true
        expect(result.failure.code).to be == :invalid_peer_message
        expect(collector.messages.size).to be == 0
      end
      failure = RSMP::Failure.new(
        code: :invalid_peer_message,
        message: 'schema error',
        source: :peer,
        context: { message: RSMP::Watchdog.new }
      )
      proxy.distribute_event RSMP::Event.new(
        type: :invalid_message,
        source: proxy,
        message: failure.context[:message],
        failure: failure
      )
      collect_task.wait
    end

    it 'can cancel if disconnect' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout, cancel: { disconnect: true }
        result = collector.collect

        expect(result.failure?).to be == true
        expect(result.failure.code).to be == :disconnected
        expect(collector.messages.size).to be == 0
      end
      failure = RSMP::Failure.new(code: :disconnected, message: 'disconnected', source: :connection)
      proxy.distribute_event RSMP::Event.new(
        type: :connection_ended,
        source: proxy,
        failure: failure
      )
      collect_task.wait
    end

    it 'can be used without num or timeout' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy
        messages = []
        result = collector.collect do |message|
          messages << message
          collector.cancel if messages.size >= 2
        end
        expect(result.failure?).to be == true
        expect(result.failure.code).to be == :cancelled
        expect(messages.size).to be == 2
        expect(collector.messages.size).to be == 0
      end
      proxy.distribute RSMP::Watchdog.new
      proxy.distribute RSMP::Watchdog.new
      collect_task.wait
    end
  end

  with '#collect!' do
    it 'raises exception if not successful' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout
        expect { collector.collect! }.to raise_exception(RSMP::OperationError)
      end
      collect_task.wait
    end

    it 'returns messages if successful' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout
        messages = collector.collect!
        expect(messages).to be_a(Array)
        expect(messages.size).to be == 1
        expect(messages.first).to be_a(RSMP::Watchdog)
      end
      proxy.distribute RSMP::Watchdog.new
      collect_task.wait
    end

    it 'raises on MessageNotAck' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      message = RSMP::StatusRequest.new
      collect_task = task.async do
        collector = subject.new(
          proxy,
          type: 'StatusUpdate',
          num: 1,
          timeout: collect_timeout,
          m_id: message.m_id
        )
        expect { collector.collect! }.to raise_exception(RSMP::OperationError)
      end
      proxy.distribute RSMP::MessageNotAck.new 'oMId' => message.m_id
      collect_task.wait
    end
  end

  with '#start' do
    it 'sets status and returns immediately' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new proxy, num: 1, timeout: collect_timeout
      collector.start
      expect(collector.active?).to be == true
    end
  end

  with '#wait' do
    it 'returns a successful Result if already complete' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new proxy, num: 1, timeout: collect_timeout
      collector.start
      proxy.distribute RSMP::Watchdog.new
      expect(collector.messages.size).to be == 1
      expect(collector.active?).to be == false
      result = collector.wait
      expect(result.success?).to be == true
      expect(result.value.messages.size).to be == 1
    end

    it 'returns a successful Result after completion' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new proxy, num: 1, timeout: collect_timeout
      collector.start
      collect_task = task.async do
        collector.wait
      end
      proxy.distribute RSMP::Watchdog.new
      result = collect_task.wait
      expect(result.success?).to be == true
      expect(collector.messages.size).to be == 1
      expect(collector.active?).to be == false
    end

    it 'returns a timeout failure' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new proxy, num: 1, timeout: collect_timeout
      collector.start
      result = collector.wait
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :timeout
    end
  end

  with '#wait!' do
    it 'returns messages if already complete' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new proxy, num: 1, timeout: collect_timeout
      collector.start
      proxy.distribute RSMP::Watchdog.new
      expect(collector.messages.size).to be == 1
      messages = collector.wait!
      expect(messages).to be_a(Array)
      expect(messages.size).to be == 1
      expect(messages.first).to be_a(RSMP::Watchdog)
    end

    it 'returns messages after completion' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new proxy, num: 1, timeout: collect_timeout
      collector.start
      collect_task = task.async do
        collector.wait!
      end
      proxy.distribute RSMP::Watchdog.new
      messages = collect_task.wait
      expect(messages).to be_a(Array)
      expect(messages.size).to be == 1
      expect(messages.first).to be_a(RSMP::Watchdog)
    end

    it 'raises OperationError on timeout' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collector = subject.new proxy, num: 1, timeout: collect_timeout
      collector.start
      expect { collector.wait! }.to raise_exception(RSMP::OperationError)
    end

    it 'raises OperationError when an invalid message ends collection' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout
        collector.start
        expect { collector.wait! }.to raise_exception(RSMP::OperationError)
      end
      message = RSMP::Watchdog.new
      failure = RSMP::Failure.new(
        code: :invalid_peer_message,
        message: 'schema error',
        source: :peer,
        context: { message: message }
      )
      proxy.distribute_event RSMP::Event.new(
        type: :invalid_message,
        source: proxy,
        message: message,
        failure: failure
      )
      collect_task.wait
    end

    it 'preserves unexpected receiver exceptions and their backtraces' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout
        expect do
          # rubocop:disable-next Lint/UnreachableLoop
          collector.collect do
            raise 'collector callback bug'
          end
        end.to raise_exception(RuntimeError, message: be =~ /collector callback bug/)
      end
      proxy.distribute RSMP::Watchdog.new
      collect_task.wait
    end
  end
end
