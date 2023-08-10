require 'async'

original = $stdout.clone
input, output = IO.pipe
STDOUT.reopen(output)
Async do |task|
  task.async do
    STDERR.puts "stdout: #{ input.gets }"
  end
  puts 'OK'
end
STDOUT.reopen original if original
puts 'done'