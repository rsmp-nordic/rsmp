RSpec.describe RSMP::AlarmCollector do
  let(:timeout) { 0.001 }
  let(:alarm) { RSMP::Alarm.new(
      'aCId' => 'A0302',
      'aSp' => 'Issue',
      'ack' => 'notAcknowledged',
      'aS' => 'Active',
      'sS' => 'notSuspended',
      'aTs' => Time.now - 60,
      'cat' => 'D',
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
          collector = RSMP::AlarmCollector.new proxy, {}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::Alarm)
        end
        proxy.notify alarm
        collect_task.wait
      end
    end

    it 'filters out wrong alarm' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, {aCId: 'A0303'}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:timeout)
        end
        proxy.notify alarm
        collect_task.wait
      end
    end

    it 'gets correct alarm' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, {aCId: 'A0302'}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::Alarm)
          expect(collector.messages.first.attribute('aCId')).to eq('A0302')
        end
        proxy.notify alarm
        collect_task.wait
      end
    end

    it 'times out' do
      RSMP::SiteProxyStub.async do |task,proxy|
        collect_task = task.async do
          collector = RSMP::AlarmCollector.new proxy, {}, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:timeout)
        end
        collect_task.wait
      end
    end
  end

end
