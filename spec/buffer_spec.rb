RSpec.describe 'Message buffering during disconnection' do
  let(:timeout) { 1 }
  let(:ip) { 'localhost' }
  let(:port) { 13111 }
  let(:site_id) { 'RN+SI0001' }
  let(:site_settings) {
    {
      'site_id' => site_id,
      'supervisors' => [
        { 'ip' => ip, 'port' => port }
      ]
    }
  }
  let(:supervisor_settings) {
    {
      'port' => port,
      'guest' => {
        'sxl' => 'tlc'
      }
    }
  }
  let(:log_settings) {
    {
      'active' => false
    }
  }
  let(:site) {
    RSMP::Site.new(
      site_settings: site_settings,
      log_settings: log_settings
    )
  }
  let(:supervisor) {
    RSMP::Supervisor.new(
      supervisor_settings: supervisor_settings,
      log_settings: log_settings
    )
  }

  describe 'message buffer edge cases' do
    let(:proxy) { 
      # Create a minimal proxy for isolated testing
      node = double('node', site_id: 'test_site')
      proxy = RSMP::Proxy.new(node: node, logger: RSMP::Logger.new('active' => false))
      proxy.send(:clear)
      proxy
    }
    
    it 'does not buffer control messages' do
      unbuffered_messages = [
        RSMP::Version.new({
          "RSMP" => [{"vers" => "3.1.5"}],
          "siteId" => [{"sId" => "RN+SI0001"}], 
          "SXL" => "1.0.15"
        }),
        RSMP::Watchdog.new({
          "wTs" => "2023-08-08T12:00:00.000Z"
        }),
        RSMP::MessageAck.new({
          "oMId" => "some-message-id"
        })
      ]
      
      unbuffered_messages.each do |msg|
        proxy.send(:buffer_message, msg)
        expect(proxy.instance_variable_get(:@message_buffer)).to be_empty
      end
    end
    
    it 'buffers data messages' do
      data_messages = [
        RSMP::StatusUpdate.new({
          "cId" => "C1",
          "sS" => [{"sCI" => "S0001", "n" => "status1", "s" => "value1", "q" => "recent"}]
        }),
        RSMP::AggregatedStatus.new({
          "cId" => "C1",
          "aSTS" => "2023-08-08T12:00:00.000Z",
          "fP" => "NormalControl",
          "fS" => "Normal",
          "se" => [false, false, false, false, false, false, false, false]
        }),
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
      ]
      
      data_messages.each_with_index do |msg, index|
        proxy.send(:buffer_message, msg)
        expect(proxy.instance_variable_get(:@message_buffer).size).to eq(index + 1)
      end
    end
    
    it 'modifies quality to "old" for status updates' do
      status_update = RSMP::StatusUpdate.new({
        "cId" => "C1",
        "sS" => [{"sCI" => "S0001", "n" => "status1", "s" => "value1", "q" => "recent"}]
      })
      
      proxy.send(:buffer_message, status_update)
      
      buffer = proxy.instance_variable_get(:@message_buffer)
      buffered_status = buffer.find { |msg| msg.type == 'StatusUpdate' }
      
      expect(buffered_status.attributes['sS'][0]['q']).to eq('old')
      expect(status_update.attributes['sS'][0]['q']).to eq('recent')
    end
    
    it 'sends and clears buffered messages' do
      # Mock the send_message method
      allow(proxy).to receive(:send_message)
      
      status_update = RSMP::StatusUpdate.new({
        "cId" => "C1", 
        "sS" => [{"sCI" => "S0001", "n" => "status1", "s" => "value1", "q" => "recent"}]
      })
      
      alarm_issue = RSMP::AlarmIssue.new({
        "aCId" => "A001",
        "xACId" => "Serious",
        "aSp" => "Issue"
      })
      
      proxy.send(:buffer_message, status_update)
      proxy.send(:buffer_message, alarm_issue)
      
      expect(proxy.instance_variable_get(:@message_buffer).size).to eq(2)
      expect(proxy).to receive(:send_message).twice
      
      proxy.send(:send_buffered_messages)
      
      expect(proxy.instance_variable_get(:@message_buffer)).to be_empty
    end
  end

  # Integration tests require full async environment - commented for now
  # These would need proper async setup and dependencies
  
  # describe 'full integration tests' do
  #   it 'buffers status updates during disconnection and sends them after reconnection' do
  #     # Full integration test would go here using AsyncRSpec
  #   end
  #   
  #   it 'maintains active subscriptions during disconnection' do
  #     # Full integration test would go here using AsyncRSpec
  #   end
  # end
end