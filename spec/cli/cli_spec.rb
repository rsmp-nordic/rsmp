RSpec.describe 'CLI rsmp', :type => :aruba do
  it 'prints help' do
    run_cli 'rsmp'
    expect_cli_output /Commands:/
 end
end