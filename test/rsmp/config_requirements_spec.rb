require 'rsmp'

describe 'Required configuration settings' do
  it 'requires cycle_time for each configured plan' do
    expect do
      RSMP::Config.validate({ 'signal_plans' => { '1' => {} } }, type: 'tlc')
    end.to raise_exception(RSMP::ConfigurationError, message: be =~ /cycle_time/)
  end

  it 'allows plans without states or dynamic bands' do
    options = RSMP::Config.validate({ 'signal_plans' => { '1' => { 'cycle_time' => 60 } } }, type: 'tlc')
    expect(options.to_h.dig('signal_plans', '1', 'cycle_time')).to be == 60
  end

  [nil, {}, { 'A' => {}, 'B' => {} }].each do |main|
    it "rejects invalid main components #{main.inspect}" do
      expect do
        RSMP::Config.validate({ 'components' => { 'main' => main } }, type: 'site')
      end.to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/components/main})
    end
  end

  it 'retains the default main component when only other groups are configured' do
    options = RSMP::Config.validate({ 'components' => { 'signal_group' => { 'G1' => {} } } }, type: 'tlc')
    expect(options.to_h.dig('components', 'main').keys).to be == ['C1']
  end

  it 'requires a main component for explicitly configured supervisor components' do
    expect do
      RSMP::Config.validate({ 'sites' => { 'example' => { 'components' => {} } } }, type: 'supervisor')
    end.to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/sites/example/components})
  end

  it 'validates supervisor site settings after inheritance without expanding stored overrides' do
    override = {
      'components' => { 'signal_group' => { 'G1' => {} } },
      'signal_plans' => { '1' => { 'states' => { 'G1' => 'a' } } }
    }
    options = RSMP::Config.validate({
                                      'default' => {
                                        'components' => { 'main' => { 'TC' => {} } },
                                        'signal_plans' => { '1' => { 'cycle_time' => 60 } }
                                      },
                                      'sites' => { 'example' => override }
                                    }, type: 'supervisor')
    expect(options.to_h.dig('sites', 'example')).to be == override
  end

  it 'rejects a new supervisor site plan without an inherited cycle time' do
    expect do
      RSMP::Config.validate({
                              'default' => { 'signal_plans' => { '1' => { 'cycle_time' => 60 } } },
                              'sites' => { 'example' => { 'signal_plans' => { '2' => {} } } }
                            }, type: 'supervisor')
    end.to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/sites/example/signal_plans/2})
  end

  it 'rejects multiple main components produced by inheritance' do
    expect do
      RSMP::Config.validate({
                              'default' => { 'components' => { 'main' => { 'A' => {} } } },
                              'sites' => { 'example' => { 'components' => { 'main' => { 'B' => {} } } } }
                            }, type: 'supervisor')
    end.to raise_exception(RSMP::ConfigurationError, message: be =~ %r{/sites/example/components/main})
  end

  it 'requires a port for a server site without supervisor endpoints' do
    expect do
      RSMP::Config.validate({ 'connection_role' => 'server', 'supervisors' => [] }, type: 'site')
    end.to raise_exception(RSMP::ConfigurationError, message: be =~ /port/)
  end

  it 'accepts an explicit server port without supervisor endpoints' do
    options = RSMP::Config.validate({
                                      'connection_role' => 'server', 'supervisors' => [], 'port' => 13_111
                                    }, type: 'site')
    expect(options.to_h['port']).to be == 13_111
  end

  it 'derives a server port from default or explicit supervisor endpoints' do
    options = RSMP::Config.validate({ 'connection_role' => 'server' }, type: 'site')
    expect(options.to_h['port']).to be == 12_111
    options = RSMP::Config.validate({
                                      'connection_role' => 'server', 'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => 13_111 }]
                                    }, type: 'site')
    expect(options.to_h['port']).to be == 13_111
  end

  it 'allows client sites without a listening port or endpoints' do
    options = RSMP::Config.validate({ 'supervisors' => [] }, type: 'site')
    expect(options.to_h['port']).to be_nil
  end

  it 'preserves the explicit validation opt-out' do
    options = RSMP::Site::Options.new({ 'signal_plans' => { '1' => {} } }, validate: false)
    expect(options.to_h['signal_plans']).to be == { '1' => {} }
  end

  it 'initializes a TLC with empty input programming and handles input changes' do
    site = RSMP::TLC::TrafficControllerSite.new(site_settings: { 'inputs' => { 'programming' => {} } })
    site.main.input_logic(1, true)
    site.main.input_logic(1, false)
    expect(site.main.handle_s0003('S0003', 'inputstatus')).to be == %w[00000000 recent]
  end
end
