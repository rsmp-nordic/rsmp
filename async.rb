require 'async'
puts 'starting...'
Async do |task|
  task.with_timeout(0.1) do
    puts 'reaading with timeout..'
    STDIN.gets
  end
end
puts 'done'