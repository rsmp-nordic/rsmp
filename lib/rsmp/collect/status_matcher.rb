module RSMP
  class StatusMatcher < Matcher
    def match_code?(item)
      return false if @want['sCI'] && @want['sCI'] != item['sCI']
      return false if @want['cO'] && @want['cO'] != item['cO']
      return false if @want['n'] && @want['n'] != item['n']

      true
    end

    def match_value?(item)
      return false if @want['q'] && @want['q'] != item['q']

      if @want['s'].is_a? Regexp
        return false if item['s'] !~ @want['s']
      elsif @want['s']
        return false if item['s'] != @want['s']
      end
      true
    end

    def match?(item)
      return nil unless match_code?(item)

      match_value?(item)
    end
  end
end
