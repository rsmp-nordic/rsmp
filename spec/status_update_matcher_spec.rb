include RSMP
RSpec.describe StatusUpdateMatcher do
  #include RSMP::SpecHelper::ConnectionHelper
  class MockProxy
    include Notifier
    def initialize
      initialize_distributor
    end
  end

  describe "#collect" do
    def build_status_message status_list
      clock = Clock.new
      RSMP::StatusUpdate.new(
        "cId" => "C1",
        "sTs" => clock.to_s,
        "sS" => [status_list].flatten
      )
    end

    let(:want) {
      {
        s5: {"sCI" => "S0005","n" => "status","s" => "False"},
        s7: {"sCI" => "S0007","n" => "status","s" => "True"},
        s11: {"sCI" => "S0011","n" => "status","s" => "False"},
      }
    }

    let(:reject) {
      {
        s5: {"sCI" => "S0005","n" => "status","s" => "True"},
        s7: {"sCI" => "S0007","n" => "status","s" => "False"},
        s11: {"sCI" => "S0011","n" => "status","s" => "True"},
      }
    }
    
    let(:proxy) { MockProxy.new }
    let(:collector) { StatusUpdateMatcher.new(proxy, want.values, timeout: 0.1) }
    
    it 'completes with a single status update' do
      Async do
        expect(collector.summary).to eq([false,false,false])
        expect(collector.done).to be(false)
        
        collector.notify build_status_message(want.values)
        expect(collector.summary).to eq([true,true,true])
        expect(collector.done).to be(true)
      end.wait
    end

    it 'completes with sequential status updates' do
      Async do
        expect(collector.summary).to eq([false,false,false])
        expect(collector.done).to be(false)

        collector.notify build_status_message(want[:s5])
        expect(collector.summary).to eq([true,false,false])
        expect(collector.done).to be(false)

        collector.notify build_status_message(want[:s7])
        expect(collector.summary).to eq([true,true,false])
        expect(collector.done).to be(false)

        collector.notify build_status_message(want[:s11])
        expect(collector.summary).to eq([true,true,true])
        expect(collector.done).to be(true)
      end.wait
    end

    it 'marks queries an not done' do
      Async do
        expect(collector.done).to be(false)
        expect(collector.summary).to eq([false,false,false])

        collector.notify build_status_message(want[:s5])      # set s5
        expect(collector.summary).to eq([true,false,false])
        expect(collector.done).to be(false)

        collector.notify build_status_message(want[:s7])
        expect(collector.summary).to eq([true,true,false])
        expect(collector.done).to be(false)

        collector.notify build_status_message(reject[:s5])    # clear s5 
        expect(collector.summary).to eq([false,true,false])
        expect(collector.done).to be(false)

        collector.notify build_status_message(want[:s11])
        expect(collector.summary).to eq([false,true,true])
        expect(collector.done).to be(false)

        collector.notify build_status_message(want[:s5])      # set s5 againt
        expect(collector.summary).to eq([true,true,true])
        expect(collector.done).to be(true)
      end.wait
    end

    it 'raises if notified adfter being complete' do
      Async do
        collector.notify build_status_message(want.values)
        expect(collector.done).to be(true)
        expect { collector.notify build_status_message(want.values) }.to raise_error(RuntimeError) 
      end.wait
    end
  end
end
