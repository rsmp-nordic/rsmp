module RSMP
  # Match a specific status response or update
  class StatusMatcher < Matcher
    # Match a status value against a matcher
    def match? item
      return nil if @want['sCI'] && @want['sCI'] != item['sCI']
      return nil if @want['cO'] && @want['cO'] != item['cO']
      return nil if @want['n'] && @want['n'] != item['n']
      return false if @want['q'] && @want['q'] != item['q']
      if @want['s'].is_a? Regexp
        return false if item['s'] !~ @want['s']
      elsif @want['s']
        return false if item['s'] != @want['s']
      end
      true
    end
  end
end