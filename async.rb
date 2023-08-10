require 'async'

error = nil
Async do |task|
  original = $stdout.clone      # keep a clone of stdout
  input, output = IO.pipe
  $stdout.reopen(output)        # set stdout to our new pipe
  task.with_timeout(1) do
    Async do
      line = input.gets
      STDERR.puts "stdout: #{line}"
    end
    puts 'OK'
    task.yield    # ensure that reader gets a chance to read
  end
rescue StandardError => e
  error = e
ensure
  $stdout.reopen original if original    # reset stdout
  raise error if error
end
puts 'Done'