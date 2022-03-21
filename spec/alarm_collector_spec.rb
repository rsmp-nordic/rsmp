RSpec.describe RSMP::AlarmCollector do
  let(:timeout) { 0.001 }
  let(:right) { RSMP::Alarm.new(
      'aCId' => 'A0302',
      'aSp' => 'Issue',
      'ack' => 'Acknowledged',
      'aS' => 'Active',
      'sS' => 'notSuspended',
      'aTs' => Time.now - 60,
      'cat' => 'D',
      'pri' => '1',
      'rvs' => [
        {
          'n' => 'color',
          'v' => 'green'
        }
      ]
    )
  }
  let(:wrong) { RSMP::Alarm.new(
      'aCId' => 'A0303',
      'aSp' => 'Suspend',
      'ack' => 'notAcknowledged',
      'aS' => 'inActive',
      'sS' => 'suspended',
      'aTs' => Time.now - 60,
      'cat' => 'T',
      'pri' => '2',
      'rvs' => [
        {
          'n' => 'color',
          'v' => 'red'
        }
      ]
    )
  }

  describe '#collect' do
    it 'gets any alarm' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, num: 2, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(2)
          expect(collector.messages.first).to be(right)
          expect(collector.messages.last).to be(wrong)
        end
        proxy.notify right
        proxy.notify wrong
        collect_task.wait
      end
    end

    it 'times out' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:timeout)
        end
        collect_task.wait
      end
    end

    it 'matches aCId' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, query: {'aCId' => 'A0302'}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.notify wrong
        proxy.notify right
        collect_task.wait
      end
    end

    it 'matches aSp' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, query: {'aSp' => 'Issue'}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.notify wrong
        proxy.notify right
        collect_task.wait
      end
    end

    it 'matches aSp with regex' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, query: {'aSp' => /[Ii]ssue/}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.notify wrong
        proxy.notify right
        collect_task.wait
      end
    end

    it 'matches ack' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, query: {'ack' => 'Acknowledged'}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.notify wrong
        proxy.notify right
        collect_task.wait
      end
    end

    it 'matches As' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, query: {'aS' => 'Active'}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.notify wrong
        proxy.notify right
        collect_task.wait
      end
    end

    it 'matches sS' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, query: {'sS' => 'notSuspended'}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.notify wrong
        proxy.notify right
        collect_task.wait
      end
    end

    it 'matches cat' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, query: {'cat' => 'D'}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.notify wrong
        proxy.notify right
        collect_task.wait
      end
    end

    it 'matches pri' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, query: {'pri' => '1'}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.notify wrong
        proxy.notify right
        collect_task.wait
      end
    end


    it 'matches rvs' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          rvs = [
            {'n' => 'color', 'v' => 'green'}
          ]
          collector = RSMP::AlarmCollector.new proxy, query: {'rvs' => rvs}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.notify wrong
        proxy.notify right
        collect_task.wait
      end
    end

  end
end
