module RSMP
  # Match a specific command responses
  class CommandMatcher < Matcher
    # Match a return value item against a matcher
    def match? item
      return nil if @want['cCI'] && @want['cCI'] != item['cCI']
      return nil if @want['n'] && @want['n'] != item['n']
      if @want['v'].is_a? Regexp
        return false if @want['v'] && item['v'] !~ @want['v']
      else
        return false if @want['v'] && item['v'] != @want['v']
      end
      true
    end
  end
end
