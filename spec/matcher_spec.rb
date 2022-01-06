RSpec.describe RSMP::Matcher do
  TIMEOUT = 0.001

  describe '#collect' do
    it 'can filter by status code' do
      RSMP::SiteProxyStub.async do |task,site_proxy|
        collect_task = task.async do |task|
          options = {
            want: [
              {"cCI"=>"M0104"}
            ],
            timeout: TIMEOUT }
          collector = RSMP::Matcher.new site_proxy, options
          result = collector.collect task, options

          expect(result).to eq(:ok)
          expect(collector.messages).to be_an(Array)
          expect(collector.messages.size).to eq(1)
          expect(collector.messages.first).to be_an(RSMP::Watchdog)
        end
        site_proxy.notify RSMP::StatusUpdate.new "cCI" => "M0104"
        collect_task.wait
      end
    end
  end
end