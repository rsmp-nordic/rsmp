RSpec.describe RSMP::AlarmCollector do
  let(:timeout) { 0.01 }
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
      'rvs' => [
        {
          'n' => 'color',
          'v' => 'green'
        }
      ]
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
      'rvs' => [
        {
          'n' => 'color',
          'v' => 'red'
        }
      ]
    )
  end

  describe '#collect' do
    it 'gets any alarm' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, num: 2, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(2)
          expect(collector.messages.first).to be(right)
          expect(collector.messages.last).to be(wrong)
        end
        proxy.distribute right
        proxy.distribute wrong
        collect_task.wait
      end
    end

    it 'times out' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, num: 1, timeout: timeout
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
          collector = described_class.new proxy, matcher: { 'cId' => 'DL1' }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end

    it 'matches aCId' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, matcher: { 'aCId' => 'A0302' }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end

    it 'matches aSp' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, matcher: { 'aSp' => 'Issue' }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end

    it 'matches aSp with regex' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, matcher: { 'aSp' => /[Ii]ssue/ }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end

    it 'matches ack' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, matcher: { 'ack' => 'Acknowledged' }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end

    it 'matches As' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, matcher: { 'aS' => 'Active' }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end

    it 'matches sS' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, matcher: { 'sS' => 'notSuspended' }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end

    it 'matches cat' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, matcher: { 'cat' => 'D' }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end

    it 'matches pri' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          collector = described_class.new proxy, matcher: { 'pri' => '1' }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end

    it 'matches rvs' do
      AsyncRSpec.async do |task|
        proxy = RSMP::SiteProxyStub.new task
        collect_task = task.async do
          rvs = [
            { 'n' => 'color', 'v' => 'green' }
          ]
          collector = described_class.new proxy, matcher: { 'rvs' => rvs }, num: 1, timeout: timeout
          result = collector.collect

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to eq(right)
        end
        proxy.distribute wrong
        proxy.distribute right
        collect_task.wait
      end
    end
  end
end
