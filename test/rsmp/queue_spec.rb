require_relative '../support/site_proxy_stub'

describe RSMP::Queue do
  let(:collect_timeout) { 0.01 }

  def failure_event(type, message: nil)
    failure = RSMP::Failure.new(code: type, message: 'test failure', source: :peer)
    RSMP::Event.new(type: type, source: self, message: message, failure: failure)
  end

  def message(type, direction, attributes = {})
    RSMP.const_get(type).new(attributes).tap { |item| item.direction = direction }
  end

  with 'filtered waits' do
    it 'discards earlier non-matches and retains messages after the match' do
      queue = subject.new(nil)
      update = message('StatusUpdate', :in, 'cId' => 'TC')
      later = RSMP::Watchdog.new
      [RSMP::Watchdog.new, message('StatusUpdate', :out, 'cId' => 'TC'),
       message('StatusUpdate', :in, 'cId' => 'OTHER'), update, later].each { |item| queue.receive(item) }
      filter = RSMP::Filter.new(type: 'StatusUpdate', outgoing: false, component: 'TC')
      expect(queue.wait_for_message(filter: filter).value).to be == update
      expect(queue.wait_for_message.value).to be == later
      expect(queue.messages).to be(:empty?)
    end

    it 'keeps the constructor filter independent of the wait filter' do
      queue = subject.new(nil, filter: RSMP::Filter.new(ingoing: false))
      queue.receive(message('StatusUpdate', :in))
      queue.receive(message('Watchdog', :out))
      update = message('StatusUpdate', :out)
      queue.receive(update)
      expect(queue.wait_for_message(filter: RSMP::Filter.new(type: 'StatusUpdate')).value).to be == update
      expect(queue.messages).to be(:empty?)
    end

    { wait_for_status_update: 'StatusUpdate', wait_for_subscribe: 'StatusSubscribe',
      wait_for_unsubscribe: 'StatusUnsubscribe' }.each do |method, type|
      it "filters code, direction and component with #{method}" do
        queue = subject.new(nil)
        attributes = { 'cId' => 'TC', 'sS' => [{ 'sCI' => 'S0014', 'n' => 'status' }] }
        queue.receive(message(type, :in, attributes))
        queue.receive(message(type, :out, attributes.merge('cId' => 'OTHER')))
        queue.receive(message(type, :out, attributes.merge('sS' => [{ 'sCI' => 'S0001' }])))
        queue.receive(message('MessageNotAck', :out, 'rea' => 'test hint'))
        expected = message(type, :out, attributes)
        queue.receive(expected)
        result = queue.public_send(method, 'S0014', direction: :out, component: 'TC', timeout: collect_timeout)
        expect(result.value).to be == expected
        expect(queue.messages).to be(:empty?)
      end
    end

    it 'matches status values as well as codes when given a matcher' do
      queue = subject.new(nil)
      attributes = { 'sS' => [{ 'sCI' => 'S0014', 'n' => 'status', 's' => 1 }] }
      queue.receive(message('StatusUpdate', :in, attributes))
      expected = message('StatusUpdate', :in, 'sS' => [{ 'sCI' => 'S0014', 'n' => 'status', 's' => 2 }])
      queue.receive(expected)
      filter = RSMP::StatusFilter.new(type: 'StatusUpdate',
                                      all: [RSMP::StatusMatcher.new('sCI' => 'S0014', 'n' => 'status', 's' => 2)])
      result = queue.wait_for_message(filter: filter)
      expect(result.value).to be == expected
    end

    { wait_for_command_request: %w[CommandRequest arg],
      wait_for_command_response: %w[CommandResponse rvs] }.each do |method, (type, key)|
      it "selects command codes, components and direction with #{method}" do
        queue = subject.new(nil)
        attributes = { 'cId' => 'TC', key => [{ 'cCI' => 'M0002', 'n' => 'status', 'v' => true }] }
        queue.receive(message(type, :out, attributes))
        queue.receive(message(type, :in, attributes.merge('cId' => 'OTHER')))
        queue.receive(message(type, :in, attributes.merge(key => [{ 'cCI' => 'M0001' }])))
        expected = message(type, :in, attributes)
        queue.receive(expected)
        expect(queue.public_send(method, 'M0002', component: 'TC', timeout: collect_timeout).value).to be == expected
        queue.receive(message(type, :out, attributes))
        expect(queue.public_send(method, 'M0002', direction: :out, timeout: collect_timeout).value.direction).to be == :out
      end
    end

    it 'uses a specific constructor filter with an unfiltered wait' do
      filter = RSMP::CommandFilter.new(type: 'CommandRequest', any: [RSMP::CommandMatcher.new('cCI' => 'M0002')])
      queue = subject.new(nil, filter: filter)
      queue.receive(message('CommandRequest', :in, 'arg' => [{ 'cCI' => 'M0001' }]))
      queue.receive(message('MessageNotAck', :in, 'oMId' => 'unrelated'))
      expected = message('CommandRequest', :in, 'arg' => [{ 'cCI' => 'M0002' }])
      queue.receive(expected)
      expect(queue.messages.size).to be == 2
      expect(queue.wait_for_message(timeout: collect_timeout).value).to be == expected
      expect(queue.messages).to be(:empty?)
    end

    it 'fails immediately on a correlated rejection admitted by specialized filters' do
      filter = RSMP::CommandFilter.new(type: 'CommandResponse',
                                       all: [RSMP::CommandMatcher.new('cCI' => 'M0002', 'v' => true)])
      queue = subject.new(nil, filter: filter)
      original = message('CommandRequest', :out)
      rejection = message('MessageNotAck', :in, 'oMId' => original.m_id, 'rea' => 'not accepted')
      queue.receive(rejection)
      result = queue.wait_for_message(filter: filter, original: original, timeout: collect_timeout)
      expect(result.failure.code).to be == :message_rejected
      expect(result.failure.context[:message]).to be == rejection
    end

    it 'can explicitly retrieve a rejection admitted by a specialized constructor filter' do
      queue = subject.new(nil, filter: RSMP::SubscriptionFilter.new(any: [RSMP::SubscriptionMatcher.new('sCI' => 'S0014')]))
      rejection = message('MessageNotAck', :in)
      queue.receive(rejection)
      expect(queue.wait_for_message(filter: RSMP::Filter.new(type: 'MessageNotAck')).value).to be == rejection
    end

    it 'wakes a pending filtered wait on a correlated NotAck instead of timing out' do
      filter = RSMP::StatusFilter.new(any: [RSMP::StatusMatcher.new('sCI' => 'S0014')])
      queue = subject.new(nil, filter: filter)
      original = message('StatusRequest', :out)
      waiter = Async::Task.current.async do
        queue.wait_for_message(filter: filter, original: original, timeout: collect_timeout)
      end
      rejection = message('MessageNotAck', :in, 'oMId' => original.m_id, 'rea' => 'unsupported')
      queue.receive(rejection)
      expect(waiter.wait.failure.code).to be == :message_rejected
    end

    it 'does not mistake a rejection for a match with a broad per-wait filter' do
      queue = subject.new(nil, filter: RSMP::StatusFilter.new)
      queue.receive(message('MessageNotAck', :in))
      expected = message('StatusUpdate', :in)
      queue.receive(expected)
      expect(queue.wait_for_message(filter: RSMP::Filter.new(ingoing: true, outgoing: false), timeout: collect_timeout).value).to be == expected
    end

    it 'correlates acknowledgements and ignores unrelated rejections and wrong directions' do
      queue = subject.new(nil)
      original = RSMP::StatusUpdate.new
      queue.receive(message('MessageAck', :in, 'oMId' => 'other'))
      queue.receive(message('MessageNotAck', :in, 'oMId' => 'other'))
      queue.receive(message('MessageAck', :out, 'oMId' => original.m_id))
      expected = message('MessageAck', :in, 'oMId' => original.m_id)
      queue.receive(expected)
      expect(queue.wait_for_ack(original, timeout: collect_timeout).value).to be == expected
    end

    it 'returns a failure for a correlated rejection' do
      queue = subject.new(nil)
      original = RSMP::StatusUpdate.new
      rejection = message('MessageNotAck', :in, 'oMId' => original.m_id, 'rea' => 'not accepted')
      queue.receive(rejection)
      result = queue.wait_for_ack(original)
      expect(result.failure.code).to be == :message_rejected
      expect(result.failure.context[:message]).to be == rejection
    end

    it 'still delivers rejections as messages when unfiltered or explicitly requested' do
      queue = subject.new(nil)
      rejection = message('MessageNotAck', :in)
      queue.receive(rejection)
      expect(queue.wait_for_message.value).to be == rejection
      queue.receive(rejection)
      expect(queue.wait_for_message(filter: RSMP::Filter.new(type: 'MessageNotAck')).value).to be == rejection
    end

    it 'uses one timeout across unrelated messages' do
      task = Async::Task.current
      queue = subject.new(nil)
      finished = false
      producer = task.async do |child|
        20.times do
          queue.receive(message('Watchdog', :in))
          child.sleep(collect_timeout / 2)
        end
        finished = true
      end
      begin
        result = queue.wait_for_subscribe('S0014', component: 'TC', timeout: collect_timeout)
        expect(result.failure.code).to be == :timeout
        expect(result.failure.message).to be(:include?, 'S0014')
        expect(result.failure.message).to be(:include?, 'on TC')
        expect(finished).to be == false
      ensure
        producer.stop
      end
    end
  end

  with 'optional failure handling' do
    { invalid_message: :invalid_message, connection_ended: :disconnect,
      missing_acknowledgement: :missing_acknowledgement }.each do |type, option|
      it "returns a sticky failure for #{type}, ahead of buffered messages" do
        queue = subject.new(nil, cancel: { option => true })
        queue.receive(RSMP::Watchdog.new)
        event = failure_event(type)
        queue.receive_event(event)
        expect(queue.wait_for_message.failure).to be == event.failure
        expect(queue.wait_for_message.failure).to be == event.failure
      end

      it "leaves #{type} handling disabled by default" do
        queue = subject.new(nil)
        queue.receive_event(failure_event(type))
        message = RSMP::Watchdog.new
        queue.receive(message)
        expect(queue.wait_for_message.value).to be == message
      end
    end

    it 'wakes a waiting consumer when a failure arrives' do
      task = Async::Task.current
      queue = subject.new(nil, cancel: { disconnect: true })
      waiter = task.async { queue.wait_for_message(timeout: collect_timeout) }
      event = failure_event(:connection_ended)
      queue.receive_event(event)
      expect(waiter.wait.failure).to be == event.failure
    end

    it 'clears buffered messages and the terminal failure before reuse' do
      queue = subject.new(nil, cancel: { disconnect: true })
      queue.receive(RSMP::Watchdog.new)
      queue.receive_event(failure_event(:connection_ended))
      queue.clear
      message = RSMP::StatusUpdate.new
      queue.receive(message)
      expect(queue.wait_for_message.value).to be == message
      expect(queue.messages).to be(:empty?)
    end

    it 'respects the message filter for invalid-message events' do
      queue = subject.new(nil, filter: RSMP::Filter.new(type: 'StatusUpdate'), cancel: { invalid_message: true })
      queue.receive_event(failure_event(:invalid_message, message: RSMP::Watchdog.new))
      message = RSMP::StatusUpdate.new
      queue.receive(message)
      expect(queue.wait_for_message.value).to be == message
      event = failure_event(:invalid_message, message: message)
      queue.receive_event(event)
      expect(queue.wait_for_message.failure).to be == event.failure
    end
  end

  with 'receiving lifecycle' do
    it 'starts receiving, retains early messages, and stops receiving' do
      proxy = RSMP::SiteProxyStub.new Async::Task.current
      queue = subject.new proxy
      queue.start
      first = RSMP::Watchdog.new
      proxy.distribute first
      queue.stop
      proxy.distribute RSMP::Watchdog.new

      expect(queue.wait_for_message!.equal?(first)).to be == true
      expect(queue.messages).to be == []
      expect(proxy.receivers).to be == []
    end
  end

  with '#handle_message' do
    it 'queues message' do
      queue = subject.new nil
      queue.receive RSMP::Watchdog.new
      queue.receive RSMP::StatusUpdate.new
      expect(queue.messages.size).to be == 2
    end
  end

  with '#wait_for_message' do
    it 'returns already queued message' do
      queue = subject.new nil
      queue.receive RSMP::Watchdog.new
      queue.receive RSMP::StatusUpdate.new

      expect(queue.wait_for_message.value).to be_a(RSMP::Watchdog)
      expect(queue.wait_for_message.value).to be_a(RSMP::StatusUpdate)
    end

    it 'returns once messages are received' do
      task = Async::Task.current
      queue = subject.new nil
      wait_task = task.async do
        got = queue.wait_for_message timeout: collect_timeout
        expect(got.success?).to be == true
        expect(got.value).to be_a(RSMP::StatusUpdate)
        expect(queue.messages).to be(:empty?)
      end
      queue.receive RSMP::StatusUpdate.new
      wait_task.wait
    end

    it 'does not return a nil success when multiple consumers wake for one message' do
      task = Async::Task.current
      queue = subject.new(nil)
      waiters = 2.times.map { task.async { queue.wait_for_message(timeout: collect_timeout) } }
      message = RSMP::StatusUpdate.new
      queue.receive(message)
      results = waiters.map(&:wait)
      expect(results.select(&:success?).map(&:value)).to be == [message]
      expect(results.select(&:failure?).map { |result| result.failure.code }).to be == [:timeout]
    end

    it 'respects filter' do
      queue = subject.new nil, filter: RSMP::Filter.new(type: 'StatusUpdate')
      queue.receive RSMP::Watchdog.new
      queue.receive RSMP::StatusUpdate.new

      expect(queue.wait_for_message.value).to be_a(RSMP::StatusUpdate)
    end

    it 'times out if no message received' do
      queue = subject.new nil
      result = queue.wait_for_message(timeout: collect_timeout)
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :timeout
      expect { queue.wait_for_message!(timeout: collect_timeout) }.to raise_exception(RSMP::OperationError)
    end

    it 'converts an outer timeout when no queue timeout was supplied' do
      queue = subject.new nil
      result = Async::Task.current.with_timeout(collect_timeout) { queue.wait_for_message }
      expect(result.failure?).to be == true
      expect(result.failure.code).to be == :timeout
      expect(result.failure.cause).to be_a(Async::TimeoutError)

      begin
        Async::Task.current.with_timeout(collect_timeout) { queue.wait_for_message! }
      rescue RSMP::OperationError => e
        failure = e.failure
      end
      expect(failure.code).to be == :timeout
      expect(failure.cause).to be_a(Async::TimeoutError)
    end
  end
end
