describe RSMP::Supervisor::Options do
  it 'accepts supervisor settings with a sites map where each site conforms to supervisor_site.json' do
    settings = {
      'port' => 12_111,
      'default' => { 'sxls' => { 'tlc' => '1.2.1' } },
      'sites' => {
        'TLC001' => {
          'sxls' => { 'tlc' => '1.2.1' },
          'supervisors' => [{ 'ip' => '127.0.0.1', 'port' => 12_111 }]
        }
      }
    }

    expect { subject.new(settings) }.not.to raise_exception
  end
end
