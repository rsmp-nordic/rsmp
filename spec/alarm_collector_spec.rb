RSpec.describe RSMP::AlarmCollector do
  let(:timeout) { 1 }
  let(:right) { RSMP::Alarm.new(
      'cId' => 'DL1',
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
      'cId' => 'TC',
      'aCId' => 'A0303',
      'aSp' => 'Suspend',
      'ack' => 'notAcknowledged',
      'aS' => 'inActive',
      'sS' => 'Suspended',
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:timeout)
        end
        collect_task.wait
      end
    end

    it 'matches cId' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, query: {'cId' => 'DL1'}, num: 1, timeout: timeout
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

    it 'matches aCId' do
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
        AsyncRSpec.async do |task|
       proxy = RSMP::SiteProxyStub.new task
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
