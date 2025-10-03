module RSMP
  class CommandMatcher < Matcher
    def match_code?(item)
      return nil if @want['cCI'] && @want['cCI'] != item['cCI']
      return nil if @want['n'] && @want['n'] != item['n']

      true
    end

    def match_value?(item)
      return true unless @want['v']

      if @want['v'].is_a? Regexp
        return false if item['v'] !~ @want['v']
      else
        return false if item['v'] != @want['v']
      end
      true
    end

    def match?(item)
      code_match = match_code?(item)
      return code_match if code_match.nil?

      match_value?(item)
    end
  end
end
