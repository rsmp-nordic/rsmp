RSpec.describe 'aruba windows', :type => :aruba do
  it 'can run command and stop' do
    run_command_and_stop('rspec --help', exit_timeout: 1, fail_on_error: false)
  end
end