require 'async'
input, output = IO.pipe
Async do
  puts "starting"
  Async do
    puts "reading..."
    line = input.gets
    puts "got #{line.inspect}"
  end
  puts "writting..."
  output.puts "hello"
end