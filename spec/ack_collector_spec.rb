RSpec.describe RSMP::Collector do
  let(:timeout) { 0.01 }
  
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
end
