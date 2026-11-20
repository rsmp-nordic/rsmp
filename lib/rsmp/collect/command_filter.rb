module RSMP
  # Select command arguments or return values within a single message.
  class CommandFilter < ItemFilter
    ITEMS = { 'CommandRequest' => 'arg', 'CommandResponse' => 'rvs' }.freeze
    MATCHER = CommandMatcher
  end
end
