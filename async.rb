require 'async'

error = nil
Async do |task|
  original = $stdout.clone
  input, output = IO.pipe
  STDOUT.reopen(output)
  task.async do
    task.with_timeout(1) do
      line = input.gets
      STDERR.puts "stdout: #{line}"
    end
  end
  puts 'OK'
rescue StandardError => e
  error = e
ensure
  STDOUT.reopen original if original
  raise error if error
end
