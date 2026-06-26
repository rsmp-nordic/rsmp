module RSMP
  # Class for matching a command
  class CommandMatcher < Matcher
    def match_code(item)
      return nil if @want['cCI'] && @want['cCI'] != item['cCI']
      return nil if @want['n'] && @want['n'] != item['n']

      true
    end

    def match_value?(item)
      return true unless @want.key?('v')
      return true if %w[undefined unknown].include?(item['age'])

      want = @want['v']
      got = item['v']
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
      code_match = match_code(item)
      return code_match if code_match.nil?

      match_value?(item)
    end
  end
end
