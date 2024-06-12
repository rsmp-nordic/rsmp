require 'async'
IO.pipe do |input, output|
  Async do
    Async do
      line = input.gets
      puts "got: #{line}"
    end
    output.puts "hello"
  end
end