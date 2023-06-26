require 'rsmp/cli'

def run_cli(cmd, exit_timeout: 5)
  cmd.unshift("cmd.exe", "/c") if ChildProcess.windows?
  run_command_and_stop(cmd, exit_timeout: exit_timeout, fail_on_error: false)
end

def expect_cli_output expected
  expect(last_command_started).to have_output expected
end