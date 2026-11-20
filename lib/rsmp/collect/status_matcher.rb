module RSMP
  # Match a specific status
  class StatusMatcher < Matcher
    include StatusItemMatching

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
  end
end
