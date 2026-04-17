require 'rsmp'
require 'sus/fixtures/async'
require_relative '../test/support/async_helper'

def test_paths
  Dir.glob('test/**/*.rb', base: @root).reject { |p| p.start_with?('test/support/') }
end

def make_registry
  registry = Sus::Registry.new(root: @root)
  registry.base.include(Sus::Fixtures::Async::ReactorContext)
  registry.base.include(AsyncHelper)
  registry
end
