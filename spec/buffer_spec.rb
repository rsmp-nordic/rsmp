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

  describe 'message buffering functionality' do
    it 'buffers status updates during disconnection and sends them after reconnection' do
      AsyncRSpec.async context: lambda {
        supervisor.start
        site.start
      } do |task|
        # Wait for initial connection
        site_proxy = supervisor.wait_for_site site_id, timeout: timeout
        supervisor_proxy = site.wait_for_supervisor ip, timeout: timeout
        
        site_proxy.wait_for_state :ready, timeout: timeout
        supervisor_proxy.wait_for_state :ready, timeout: timeout
        
        # Create a status subscription to verify continuous operation
        subscription_msg = RSMP::StatusSubscribe.new({
          "cId" => "C1",
          "sS" => [{"sCI" => "S0001", "n" => "status1", "uRt" => 1000}]
        })
        
        # Send subscription before disconnection
        site_proxy.send_message subscription_msg
        
        # Verify buffer is initially empty
        expect(supervisor_proxy.instance_variable_get(:@message_buffer)).to be_empty
        
        # Simulate disconnection by closing the site proxy connection
        site_proxy.close
        
        # Wait for disconnection to be processed
        supervisor_proxy.wait_for_state :disconnected, timeout: timeout
        
        # During disconnection, try to send messages that should be buffered
        status_update = RSMP::StatusUpdate.new({
          "cId" => "C1",
          "sS" => [{"sCI" => "S0001", "n" => "status1", "s" => "test_value", "q" => "recent"}]
        })
        
        alarm_issue = RSMP::AlarmIssue.new({
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
        
        # Try to send messages during disconnection - they should be buffered
        supervisor_proxy.send_message status_update
        supervisor_proxy.send_message alarm_issue
        
        # Verify messages are buffered
        buffer = supervisor_proxy.instance_variable_get(:@message_buffer)
        expect(buffer.size).to eq(2)
        
        # Verify status update quality was changed to "old"
        buffered_status = buffer.find { |msg| msg.type == 'StatusUpdate' }
        expect(buffered_status.attributes['sS'][0]['q']).to eq('old')
        
        # Verify original message quality is preserved
        expect(status_update.attributes['sS'][0]['q']).to eq('recent')
        
        # Try to send control messages - they should not be buffered
        version_msg = RSMP::Version.new({
          "RSMP" => [{"vers" => "3.1.5"}],
          "siteId" => [{"sId" => "RN+SI0001"}], 
          "SXL" => "1.0.15"
        })
        
        supervisor_proxy.send_message version_msg
        
        # Buffer should still contain only the 2 data messages
        expect(supervisor_proxy.instance_variable_get(:@message_buffer).size).to eq(2)
        
        # Now reconnect
        site.start
        
        # Wait for reconnection
        supervisor_proxy.wait_for_state :ready, timeout: timeout
        
        # Verify buffered messages were sent and buffer is cleared
        expect(supervisor_proxy.instance_variable_get(:@message_buffer)).to be_empty
        
        task.stop
      end
    end
    
    it 'maintains active subscriptions during disconnection' do
      AsyncRSpec.async context: lambda {
        supervisor.start
        site.start
      } do |task|
        # Wait for initial connection
        site_proxy = supervisor.wait_for_site site_id, timeout: timeout
        supervisor_proxy = site.wait_for_supervisor ip, timeout: timeout
        
        site_proxy.wait_for_state :ready, timeout: timeout
        supervisor_proxy.wait_for_state :ready, timeout: timeout
        
        # Create a status subscription
        subscription_msg = RSMP::StatusSubscribe.new({
          "cId" => "C1",
          "sS" => [{"sCI" => "S0001", "n" => "status1", "uRt" => 1000}]
        })
        
        site_proxy.send_message subscription_msg
        
        # Verify subscription is active
        subscriptions = supervisor_proxy.instance_variable_get(:@status_subscriptions)
        expect(subscriptions["C1"]).not_to be_nil
        expect(subscriptions["C1"]["S0001"]).not_to be_nil
        expect(subscriptions["C1"]["S0001"]["status1"]).not_to be_nil
        
        # Simulate disconnection
        site_proxy.close
        supervisor_proxy.wait_for_state :disconnected, timeout: timeout
        
        # Verify subscription is still maintained during disconnection
        expect(subscriptions["C1"]["S0001"]["status1"]).not_to be_nil
        
        # Reconnect
        site.start
        supervisor_proxy.wait_for_state :ready, timeout: timeout
        
        # Verify subscription is still active after reconnection
        expect(subscriptions["C1"]["S0001"]["status1"]).not_to be_nil
        
        task.stop
      end
    end
  end
  
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
  end
end