require_relative '../support/site_proxy_stub'

describe RSMP::AlarmCollector do
  let(:collect_timeout) { 0.01 }
  let(:right) do
    RSMP::Alarm.new(
      'cId' => 'DL1',
      'aCId' => 'A0302',
      'aSp' => 'Issue',
      'ack' => 'Acknowledged',
      'aS' => 'Active',
      'sS' => 'notSuspended',
      'aTs' => Time.now - 60,
      'cat' => 'D',
      'pri' => '1',
      'rvs' => [{ 'n' => 'color', 'v' => 'green' }]
    )
  end
  let(:wrong) do
    RSMP::Alarm.new(
      'cId' => 'TC',
      'aCId' => 'A0303',
      'aSp' => 'Suspend',
      'ack' => 'notAcknowledged',
      'aS' => 'inActive',
      'sS' => 'Suspended',
      'aTs' => Time.now - 60,
      'cat' => 'T',
      'pri' => '2',
      'rvs' => [{ 'n' => 'color', 'v' => 'red' }]
    )
  end

  with '#collect' do
    it 'gets any alarm' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 2, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right, wrong]
      end
      proxy.distribute right
      proxy.distribute wrong
      collect_task.wait
    end

    it 'times out' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :timeout
      end
      collect_task.wait
    end

    it 'matches cId' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, matcher: { 'cId' => 'DL1' }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end

    it 'matches aCId' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, matcher: { 'aCId' => 'A0302' }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end

    it 'matches aSp' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, matcher: { 'aSp' => 'Issue' }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end

    it 'matches aSp with regex' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, matcher: { 'aSp' => /[Ii]ssue/ }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end

    it 'matches ack' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, matcher: { 'ack' => 'Acknowledged' }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end

    it 'matches As' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, matcher: { 'aS' => 'Active' }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end

    it 'matches sS' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, matcher: { 'sS' => 'notSuspended' }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end

    it 'matches cat' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, matcher: { 'cat' => 'D' }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end

    it 'matches pri' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        collector = subject.new proxy, matcher: { 'pri' => '1' }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end

    it 'matches rvs' do
      task = Async::Task.current
      proxy = RSMP::SiteProxyStub.new task
      collect_task = task.async do
        rvs = [{ 'n' => 'color', 'v' => 'green' }]
        collector = subject.new proxy, matcher: { 'rvs' => rvs }, num: 1, timeout: collect_timeout
        result = collector.collect

        expect(result).to be == :ok
        expect(collector.messages).to be == [right]
      end
      proxy.distribute wrong
      proxy.distribute right
      collect_task.wait
    end
  end
end
