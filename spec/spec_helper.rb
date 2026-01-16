# Silence this warning:
# ruby/4.0.1/lib/ruby/4.0.0/resolv.rb:207: warning: IO::Buffer is experimental and both the Ruby and C interface may change in the future!
# See https://github.com/socketry/io-event/issues/82begin
Warning[:experimental] = begin
  false
rescue StandardError
  nil
end

require 'bundler/setup'
require_relative '../lib/rsmp'
require_relative 'support/site_proxy_stub'
require_relative 'support/async_rspec'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

include RSpec
