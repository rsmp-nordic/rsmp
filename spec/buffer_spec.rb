RSpec.describe RSMP::Proxy do
  let(:logger) { RSMP::Logger.new('active' => false) }
  
  describe 'message buffering' do
    let(:node) { double('node', site_id: 'test_site') }
    let(:proxy) do
      # Create a minimal proxy instance for testing
      proxy = RSMP::Proxy.new(node: node, logger: logger)
      proxy.send(:clear)  # Initialize the buffer
      proxy
    end
    
    let(:status_update) do
      RSMP::StatusUpdate.new({
        "cId" => "C1",
        "sS" => [{"sCI" => "S0001", "n" => "status1", "s" => "value1", "q" => "recent"}]
      })
    end
    
    let(:version_message) do
      RSMP::Version.new({
        "RSMP" => [{"vers" => "3.1.5"}],
        "siteId" => [{"sId" => "RN+SI0001"}], 
        "SXL" => "1.0.15"
      })
    end
    
    let(:watchdog_message) do
      RSMP::Watchdog.new({
        "wTs" => "2023-08-08T12:00:00.000Z"
      })
    end
    
    let(:alarm_issue) do
      RSMP::AlarmIssue.new({
        "aCId" => "A001",
        "xACId" => "Serious",
        "xNACId" => "100",
        "aSp" => "Issue",
        "ack" => "notAcknowledged",
        "aS" => "Active",
        "sS" => "notSuspended",
        "aTs" => "2023-08-08T12:00:00.000Z",
        "cat" => "D",
        "pri" => "2",
        "rvs" => [{"n" => "status", "v" => "some value"}]
      })
    end
    
    describe '#buffer_message' do
      it 'buffers StatusUpdate messages' do
        expect { proxy.send(:buffer_message, status_update) }.to_not raise_error
        expect(proxy.instance_variable_get(:@message_buffer).size).to eq(1)
      end
      
      it 'buffers AlarmIssue messages' do
        expect { proxy.send(:buffer_message, alarm_issue) }.to_not raise_error
        expect(proxy.instance_variable_get(:@message_buffer).size).to eq(1)
      end
      
      it 'does not buffer Version messages' do
        expect { proxy.send(:buffer_message, version_message) }.to_not raise_error
        expect(proxy.instance_variable_get(:@message_buffer)).to be_empty
      end
      
      it 'does not buffer Watchdog messages' do
        expect { proxy.send(:buffer_message, watchdog_message) }.to_not raise_error
        expect(proxy.instance_variable_get(:@message_buffer)).to be_empty
      end
    end
    
    describe '#clone_message_for_buffer' do
      it 'sets quality to "old" for StatusUpdate messages' do
        cloned = proxy.send(:clone_message_for_buffer, status_update)
        expect(cloned.attributes['sS'][0]['q']).to eq('old')
      end
      
      it 'preserves original message quality' do
        proxy.send(:clone_message_for_buffer, status_update)
        expect(status_update.attributes['sS'][0]['q']).to eq('recent')
      end
      
      it 'does not modify non-status messages' do
        cloned = proxy.send(:clone_message_for_buffer, alarm_issue)
        expect(cloned.attributes).to eq(alarm_issue.attributes)
      end
    end
    
    describe '#send_buffered_messages' do
      before do
        # Mock the send_message method to avoid actual network calls
        allow(proxy).to receive(:send_message)
      end
      
      it 'sends all buffered messages' do
        # Add some messages to the buffer
        proxy.send(:buffer_message, status_update)
        proxy.send(:buffer_message, alarm_issue)
        
        expect(proxy).to receive(:send_message).twice
        proxy.send(:send_buffered_messages)
      end
      
      it 'clears the buffer after sending' do
        proxy.send(:buffer_message, status_update)
        proxy.send(:send_buffered_messages)
        
        expect(proxy.instance_variable_get(:@message_buffer)).to be_empty
      end
      
      it 'does nothing when buffer is empty' do
        expect(proxy).to_not receive(:send_message)
        proxy.send(:send_buffered_messages)
      end
    end
  end
end