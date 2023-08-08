require 'rsmp/cli'

def expect_stdout look_for, timeout: 2
  original = $stdout.clone      # keep a clone of stdout
  input, output = IO.pipe
  $stdout.reopen(output)        # set stdout to our new pipe
  error = nil
  Async do |task|
    reader = nil
    task.with_timeout(timeout) do
      reader = Async do
        while line = input.gets         # read from pipe to receives what's written to stdout
          STDERR.puts "stdout: #{line}"
          #$stderr.puts "Stdout: #{line}"
          task.stop if look_for.is_a?(String) && line.include?(look_for)
          task.stop if look_for.is_a?(Regexp) && look_for.match(line)
        end
      end
      yield
      task.yield    # ensure that reader gets a chance to read
      raise "Did not write #{look_for.inspect} to stdout"
    end
  rescue Async::TimeoutError => e
    error = RuntimeError.new "Did not write #{look_for.inspect} to stdout within #{timeout}s"
  rescue StandardError => e
    error = e
  ensure
    task.stop
  end.wait
ensure
  $stdout.reopen original if original    # reset stdout
  raise error if error
end
