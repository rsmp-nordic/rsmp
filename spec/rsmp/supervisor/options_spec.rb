RSpec.describe RSMP::Supervisor::Options do
  it 'accepts supervisor settings with a sites map where each site conforms to supervisor_site.json' do
    settings = {
      'port' => 12_111,
      'default' => { 'sxl' => 'tlc' },
      'sites' => {
        'TLC001' => {
          'sxl' => 'tlc',
          'sxl_version' => '1.2.1',
          'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => 12_111 }]
        }
      }
    }

    expect { described_class.new(settings) }.not_to raise_error
  end
end
