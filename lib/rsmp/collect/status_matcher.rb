module RSMP
  # Match a specific status
  class StatusMatcher < Matcher
    def match_code(item)
      return nil if @want['sCI'] && @want['sCI'] != item['sCI']
      return nil if @want['cO'] && @want['cO'] != item['cO']
      return nil if @want['n'] && @want['n'] != item['n']

      true
    end

    def match_value?(item)
      return false if @want['q'] && @want['q'] != item['q']
      return true unless @want.key?('s')

      want = @want['s']
      got = item['s']
      if want.is_a? Regexp
        return false unless regex_match?(got, want)
      elsif got != want
        return false
      end
      true
    end

    def regex_match?(got, want)
      return got =~ want if got.is_a?(String)
      return got.any? { |item| item.is_a?(String) && item =~ want } if got.is_a?(Array)

      false
    end

    def match(item)
      return nil unless match_code(item)

      match_value?(item)
    end
  end
end
