include RSMP
RSpec.describe StatusUpdateMatcher do
  let(:timeout) { 0.001 }

  describe "#collect" do
    def build_status_message status_list
      clock = Clock.new
      RSMP::StatusUpdate.new(
        "cId" => "C1",
        "sTs" => clock.to_s,
        "sS" => [status_list].flatten
      )
    end

    let(:ok) {
      {
        s5: {"sCI" => "S0005","n" => "status","s" => "False"},
        s7: {"sCI" => "S0007","n" => "status","s" => "True"},
        s11: {"sCI" => "S0011","n" => "status","s" => "False"},
      }
    }

    let(:want) {
      {
        s5: {"sCI" => "S0005","n" => "status","s" => "False"},
        s7: {"sCI" => "S0007","n" => "status","s" => /^True(,True)*$/},
        s11: {"sCI" => "S0011","n" => "status","s" => /^False(,False)*$/},
      }
    }

    let(:reject) {
      {
        s5: {"sCI" => "S0005","n" => "status","s" => "True"},
        s7: {"sCI" => "S0007","n" => "status","s" => "False"},
        s11: {"sCI" => "S0011","n" => "status","s" => "True"},
      }
    }
    
    let(:proxy) { SiteProxyStub.new }
    let(:collector) { StatusUpdateMatcher.new(proxy, want.values, timeout: timeout) }
    
    it 'completes with a single status update' do
      Async do
        expect(collector.summary).to eq([false,false,false])
        expect(collector.done?).to be(false)
        
        collector.notify build_status_message(ok.values)
        expect(collector.summary).to eq([true,true,true])
        expect(collector.done?).to be(true)
      end
    end

    it 'completes with sequential status updates' do
      Async do
        expect(collector.summary).to eq([false,false,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s5])
        expect(collector.summary).to eq([true,false,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s7])
        expect(collector.summary).to eq([true,true,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s11])
        expect(collector.summary).to eq([true,true,true])
        expect(collector.done?).to be(true)
      end
    end

    it 'marks queries as not done' do
      Async do
        expect(collector.done?).to be(false)
        expect(collector.summary).to eq([false,false,false])

        collector.notify build_status_message(ok[:s5])      # set s5
        expect(collector.summary).to eq([true,false,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s7])
        expect(collector.summary).to eq([true,true,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(reject[:s5])    # clear s5 
        expect(collector.summary).to eq([false,true,false])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s11])
        expect(collector.summary).to eq([false,true,true])
        expect(collector.done?).to be(false)

        collector.notify build_status_message(ok[:s5])      # set s5 againt
        expect(collector.summary).to eq([true,true,true])
        expect(collector.done?).to be(true)
      end
    end

    it 'raises if notified after being complete' do
      Async do
        collector.notify build_status_message(ok.values)
        expect(collector.done?).to be(true)
        expect { collector.notify build_status_message(ok.values) }.to raise_error(RuntimeError)
      end
    end

    it 'extra status updates are ignored' do
      Async do |task|
        # proxy should have no listeners initially
        expect(proxy.listeners.size).to eq(0)

        # start collection
        collect_task = task.async do
          collector.collect task
        end

        # collector should have inserted inself as a listener on the proxy
        expect(proxy.listeners.size).to eq(1)
        expect(collector.done?).to be(false)

        # send required values
        proxy.notify build_status_message(ok.values)

        # should be done, and should have rmeoved itself as a listener
        expect(collector.done?).to be(true)
        expect(proxy.listeners.size).to eq(0)

        # additional messages should there not reach the collector, and should not affect the result
        proxy.notify build_status_message(reject.values)
        expect(collector.done?).to be(true)
      end
    end
  end
end
