RSpec.describe 'Connection stability after handshake' do
  let(:timeout) { 1 }
  let(:ip) { 'localhost' }
  let(:port) { 13_112 }
  let(:site_id) { 'RN+SI0001' }

  # Use short intervals to trigger the bug quickly
  let(:site_settings) do
    {
      'site_id' => site_id,
      'supervisors' => [
        { 'ip' => ip, 'port' => port }
      ],
      'sxl' => 'tlc',
      'sxl_version' => '1.2.1',
      'send_after_connect' => true, # Enable sending initial state after connection
      'intervals' => {
        'timer' => 0.1,
        'watchdog' => 0.1,
        'reconnect' => 0.1
      },
      'timeouts' => {
        'watchdog' => 0.2,
        'acknowledgement' => 0.2
      },
      'components' => {
        'main' => {
          'TC' => {
            'ntsOId' => 'KK+AG9998=001TC000'
          }
        }
      },
      'alarms' => {
        'A0001' => { 'description' => 'Test alarm' }
      }
    }
  end

  let(:supervisor_settings) do
    {
      'port' => port,
      'guest' => {
        'sxl' => 'tlc'
      },
      'intervals' => {
        'timer' => 0.1,
        'watchdog' => 0.1
      },
      'timeouts' => {
        'watchdog' => 0.2,
        'acknowledgement' => 0.2
      }
    }
  end

  let(:log_settings) do
    {
      'active' => true,
      'color' => true,
      'timestamp' => false,
      'level' => 'debug'
    }
  end

  let(:site) do
    RSMP::TLC::TrafficControllerSite.new(
      site_settings: site_settings,
      log_settings: log_settings
    )
  end

  let(:supervisor) do
    RSMP::Supervisor.new(
      supervisor_settings: supervisor_settings,
      log_settings: log_settings
    )
  end

  it 'maintains stable connection after handshake without reconnecting' do
    reconnect_count = 0

    # Capture log output to count reconnections
    log_output = StringIO.new
    original_stdout = $stdout
    original_stderr = $stderr

    AsyncRSpec.async context: lambda {
      # Redirect output to capture reconnection messages
      $stdout = log_output
      $stderr = log_output

      supervisor.start
      supervisor.ready_condition.wait
      site.start
    } do |task|
      # Wait for initial connection
      site_proxy = supervisor.wait_for_site site_id, timeout: timeout
      supervisor_proxy = site.wait_for_supervisor ip, timeout: timeout

      # Wait for handshake to complete
      site_proxy.wait_for_state :ready, timeout: timeout
      supervisor_proxy.wait_for_state :ready, timeout: timeout

      expect(site_proxy.state).to eq(:ready)
      expect(supervisor_proxy.state).to eq(:ready)

      # Wait for 0.5 seconds to see if any reconnections occur
      # This is enough time for multiple timer ticks (timer runs every 0.1s)
      task.sleep 0.5

      # Restore output and count reconnections
      $stdout = original_stdout
      $stderr = original_stderr

      log_text = log_output.string
      reconnect_count = log_text.scan('Will try to reconnect').size

      # On a working system, there should be 0 or 1 reconnect message
      # (1 is logged right after initial connection as part of setup)
      # On a buggy system, there will be many reconnect messages
      expect(reconnect_count).to be <= 1,
                                 "Expected at most 1 reconnection message but got #{reconnect_count}. This indicates a disconnect-reconnect loop."

      task.stop
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end
  end
end
