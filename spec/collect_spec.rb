RSpec.describe RSMP::Proxy do
  include RSMP::SpecHelper::ConnectionHelper
  
  describe '#collect' do
    it 'gets a Watchdog' do
      with_site_connected do |task, supervisor, site, site_proxy, supervisor_proxy|
        collector = site_proxy.collect task, type: "Watchdog", timeout: 0.1
        expect(collector).to be_an(RSMP::Collector)
        messages = collector.messages
        expect(messages).to be_an(Array)
        expect(messages.size).to eq(1)
        expect(messages.first).to be_an(RSMP::Watchdog)
      end
    end    

    it 'gets two Watchdogs' do
      with_site_connected do |task, supervisor, site, site_proxy, supervisor_proxy|
        collector = site_proxy.collect task, type: "Watchdog", num: 2, timeout: 0.1
        messages = collector.messages
        expect(messages).to be_an(Array)
        expect(messages.size).to eq(2)
        expect(messages.first).to be_an(RSMP::Watchdog)
        expect(messages.last).to be_an(RSMP::Watchdog)
      end
    end    

    it 'times out' do
      with_site_connected do |task, supervisor, site, site_proxy, supervisor_proxy|
        collect_task = task.async { site_proxy.collect task, type: "AggregatedStatus", num: 1000, timeout: 0.1 }
        expect { collect_task.wait }.to raise_error(RSMP::TimeoutError) 
      end
    end
  end

  describe "#collect_aggregated_status" do
    it 'gets an AggregatedStatus' do
      with_site_connected do |task, supervisor, site, site_proxy, supervisor_proxy|
        collect_task = task.async { site_proxy.collect_aggregated_status task, timeout: 0.1 }
        collector = collect_task.wait
        expect(collector.messages.first).to be_an(RSMP::AggregatedStatus)
      end
    end
  
    it 'times out' do
      with_site_connected do |task, supervisor, site, site_proxy, supervisor_proxy|
        # an aggreagated status is send by the site right after connection, so ask for more
        collect_task = task.async { site_proxy.collect_aggregated_status task, num: 1000, timeout: 0.1 }
        expect { collect_task.wait }.to raise_error(RSMP::TimeoutError) 
      end
    end

    it 'cancels if a schema error is received' do
      with_site_connected do |task, supervisor, site, site_proxy, supervisor_proxy|
        status_list = [
          {"sCI" => "S0005","n" => "status","s" => "False"}
        ]
        # tell the supervisor to collect status updates
        collect_task = task.async do
          site_proxy.collect_status_updates task, status_list, timeout: 1
        end

        # send an invalid status update from the site
        message = RSMP::StatusUpdate.new({
        #  "cId" => 'C1',             # leaving this our makes the message invalid
          "sTs" => RSMP::Clock.to_s,
          "sS" => status_list.map { |item| item.merge('q'=>'recent') }
        })
        supervisor_proxy.send_message message, validate: false

        # expect the collect to cancel
        expect { collect_task.wait }.to raise_error(RSMP::SchemaError)
      end
    end

    it 'cancels if a disconnect happens' do
      with_site_connected do |task, supervisor, site, site_proxy, supervisor_proxy|
        status_list = [
          {"sCI" => "S0005","n" => "status","s" => "False"}
        ]
        # tell the supervisor to collect status updates
        collect_task = task.async do
          site_proxy.collect_status_updates task, status_list, timeout: 1, cancel: {disconnect: true}
        end

        # close the connection
        supervisor_proxy.stop

        # expect the collect to cancel
        expect { collect_task.wait }.to raise_error(RSMP::ConnectionError)
      end
    end
  end
end
