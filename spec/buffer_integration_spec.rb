RSpec.describe 'Message buffering during disconnection' do
  let(:timeout) { 0.1 }
  let(:log_settings) { { 'active' => false } }
  
  let(:supervisor_settings) do
    {
      'port' => 13112,  # Use unique port to avoid conflicts
      'log' => log_settings
    }
  end
  
  let(:site_settings) do
    {
      'site_id' => 'RN+SI0001',
      'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => 13112 }],
      'log' => log_settings,
      'send_after_connect' => false,  # Disable to focus on buffer testing
      'intervals' => { 'reconnect' => 0.01 }  # Fast reconnect for testing
    }
  end
  
  it 'buffers messages during disconnection and sends them after reconnection' do
    messages_received = []
    
    # Start supervisor
    supervisor = RSMP::Supervisor.new(supervisor_settings: supervisor_settings)
    
    AsyncRSpec.async context: lambda { supervisor.start } do |task|
      # Start site
      site = RSMP::Site.new(site_settings: site_settings)
      site.start
      
      # Wait for connection
      proxy = site.wait_for_supervisor(:any, timeout: timeout)
      expect(proxy).to be_a(RSMP::SupervisorProxy)
      proxy.wait_for_state(:ready, timeout: timeout)
      
      # Get supervisor side proxy
      supervisor_proxy = supervisor.wait_for_site('RN+SI0001', timeout: timeout)
      
      # Set up message collection on supervisor side
      supervisor_proxy.start_distribute do |message|
        if message.is_a?(RSMP::StatusUpdate)
          messages_received << message
        end
      end
      
      # Create a test component to generate status updates
      component = site.components['main'] || site.add_component('main')
      
      # Close the connection to simulate disconnection
      proxy.close
      
      # Wait for disconnection
      proxy.wait_for_state(:disconnected, timeout: timeout)
      
      # Send status updates while disconnected - these should be buffered
      3.times do |i|
        update = RSMP::StatusUpdate.new({
          "cId" => "main",
          "sTs" => Time.now.strftime('%Y-%m-%dT%H:%M:%S.%LZ'),
          "sS" => [{"sCI" => "S0001", "n" => "test_status_#{i}", "s" => "value_#{i}", "q" => "recent"}]
        })
        
        # This should buffer the message instead of sending it
        expect { proxy.send(:send_message, update) }.to_not raise_error
      end
      
      # Verify messages are buffered
      buffer = proxy.instance_variable_get(:@message_buffer)
      expect(buffer.size).to eq(3)
      
      # Verify buffered messages have quality 'old'
      buffer.each do |buffered_message|
        expect(buffered_message.attributes['sS'][0]['q']).to eq('old')
      end
      
      # Reconnect
      proxy.revive({
        settings: site_settings,
        collect: nil
      })
      
      # Wait for reconnection and buffered messages to be sent
      proxy.wait_for_state(:ready, timeout: timeout)
      
      # Allow some time for buffered messages to be processed
      task.sleep(0.05)
      
      # Verify buffer is cleared after sending
      expect(proxy.instance_variable_get(:@message_buffer)).to be_empty
      
      # Verify buffered messages were received with 'old' quality
      expect(messages_received.size).to eq(3)
      messages_received.each do |message|
        expect(message.attributes['sS'][0]['q']).to eq('old')
      end
    end
  end
end