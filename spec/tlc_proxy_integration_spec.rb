RSpec.describe RSMP::TLCProxy, "integration" do
  include AsyncRSpec

  let(:timeout) { 0.05 }
  let(:settings) do
    {
      'log' => {
        'active' => false
      },
      'timeouts' => {
        'watchdog' => timeout,
        'acknowledgement' => timeout
      },
      'intervals' => {
        'watchdog' => timeout,
        'timer' => timeout,
        'after_connect' => 0.01,
        'reconnect' => timeout
      }
    }
  end

  let(:supervisor_settings) do
    settings.merge({
      'port' => 13223,    # use unique port for this test
      'guest' => {
        'sxl' => 'tlc'
      }
    })
  end

  let(:site_settings) do
    settings.merge({
      'site_id' => 'RN+SI0001',
      'supervisors' => [
        {
          'ip' => '127.0.0.1',
          'port' => 13223
        }
      ],
      'sxl' => 'tlc',
      'sxl_version' => '1.2.1'
    })
  end

  it 'can be created and used with proper site proxy' do
    # This is a simpler test that just shows the TLCProxy can be instantiated
    # and used without requiring a full supervisor/site connection
    site_proxy = double('SiteProxy')
    allow(site_proxy).to receive(:send_command)
    allow(site_proxy).to receive(:request_status)

    tlc_proxy = RSMP::TLCProxy.new(site_proxy, 'TC')
    
    expect(tlc_proxy.site_proxy).to eq(site_proxy)
    expect(tlc_proxy.component_id).to eq('TC')

    # Test the methods can be called
    expect { tlc_proxy.set_signal_plan(1) }.not_to raise_error
    expect { tlc_proxy.fetch_signal_plan }.not_to raise_error

    # Verify the underlying methods were called
    expect(site_proxy).to have_received(:send_command).once
    expect(site_proxy).to have_received(:request_status).once
  end
end