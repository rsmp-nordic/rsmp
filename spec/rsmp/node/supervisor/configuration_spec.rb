RSpec.describe RSMP::Supervisor::Modules::Configuration do
  it 'raises configuration error when a site entry is missing sxl' do
    settings = {
      'port' => 12_111,
      'default' => { 'sxl' => 'tlc' },
      'sites' => {
        'TLC001' => { 'type' => 'tlc' } # missing 'sxl'
      }
    }

    expect do
      RSMP::Supervisor.new(supervisor_settings: settings, log_settings: { 'active' => false })
    end.to raise_error(RSMP::ConfigurationError)
  end
end
