require 'async'
require_relative 'spec/support/cli_helper.rb'

puts 'starting...'
Async do |task|
  expect_stdout( 'OK') do
    puts 'before'
    puts 'OK'
    puts 'after'
    #RSMP::CLI.new.invoke('site')
  end
end
puts 'done'