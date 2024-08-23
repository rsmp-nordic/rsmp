module RSMP
  # Match a specific alarm
  class AlarmMatcher < Matcher
    # Match an alarm value against a matcher
    def match? item
      return false if @want['n'] && @want['n'] != item['n']
      if @want['v'].is_a? Regexp
        return false if item['v'] !~ @want['v']
      elsif @want['v']
        return false if item['v'] != @want['v']
      end
      true
    end
  end
end