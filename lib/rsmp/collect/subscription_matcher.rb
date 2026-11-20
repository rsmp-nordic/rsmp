module RSMP
  # Matches one StatusSubscribe or StatusUnsubscribe item. Only explicitly
  # requested subscription settings are checked; false is a meaningful value.
  class SubscriptionMatcher < Matcher
    include StatusItemMatching

    def match_value?(item)
      %w[uRt sOc].all? { |key| !@want.key?(key) || @want[key] == item[key] }
    end
  end
end
