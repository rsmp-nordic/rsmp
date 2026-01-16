module RSMP
  # Match a specific alarm
  class AlarmMatcher < Matcher
    def match(item)
      return nil if @want['n'] && @want['n'] != item['n']

      if @want['v'].is_a? Regexp
        return nil if item['v'] !~ @want['v']
      elsif @want['v']
        return nil if item['v'] != @want['v']
      end
      true
    end
  end
end
