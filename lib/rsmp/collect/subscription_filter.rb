module RSMP
  # Select subscription items, independently of status values.
  class SubscriptionFilter < ItemFilter
    ITEMS = { 'StatusSubscribe' => 'sS', 'StatusUnsubscribe' => 'sS' }.freeze
    MATCHER = SubscriptionMatcher
  end
end
