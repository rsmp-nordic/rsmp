RSpec.describe 'CLI rsmp help', :type => :aruba do
  describe 'with no options' do
    it 'prints help' do
      run_cli 'rsmp help'
      expect_cli_output /Commands:/
    end
  end

  describe 'site' do
    it 'prints site help' do
      run_cli 'rsmp help site'
      expect_cli_output /Usage:/
    end
  end

  it 'can run command and stop' do
    run_command_and_stop('rspec --help', exit_timeout: 1, fail_on_error: false)
  end
end