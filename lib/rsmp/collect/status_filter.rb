module RSMP
  # Select status values within a single update or response.
  class StatusFilter < ItemFilter
    ITEMS = { 'StatusUpdate' => 'sS', 'StatusResponse' => 'sS' }.freeze
    MATCHER = StatusMatcher
  end
end
