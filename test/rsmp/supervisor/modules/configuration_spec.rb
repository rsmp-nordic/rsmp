describe RSMP::Supervisor::Modules::Configuration do
  it 'raises configuration error when a site entry is missing sxls' do
    settings = {
      'port' => 12_111,
      'default' => { 'sxls' => { 'tlc' => '1.2.1' } },
      'sites' => {
        'TLC001' => { 'type' => 'tlc' } # missing 'sxls'
      }
    }

    expect do
      RSMP::Supervisor.new(supervisor_settings: settings, log_settings: { 'active' => false })
    end.to raise_exception(RSMP::ConfigurationError)
  end
end
