require 'bundler/setup'
require 'rsmp'
require_relative 'support/connection_helper'
require_relative 'support/site_proxy_stub'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

include RSpec


def async_context &block
  Async do |task|
    yield task
    task.reactor.stop
  end
end

def async_context terminate:true, &block
  Async do |task|
    yield task
    task.reactor.stop if terminate
  end.result
end