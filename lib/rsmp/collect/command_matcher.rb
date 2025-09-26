module RSMP
  # Match a specific command responses
  class CommandMatcher < Matcher
    # Match a return value item against a matcher
    def match?(item)
      return unless matches_component?(item)
      return unless matches_name?(item)

      matches_value?(item)
    end

    private

    def matches_component?(item)
      return true unless @want['cCI']

      @want['cCI'] == item['cCI']
    end

    def matches_name?(item)
      return true unless @want['n']

      @want['n'] == item['n']
    end

    def matches_value?(item)
      case @want['v']
      when NilClass
        true
      when Regexp
        item['v'] =~ @want['v'] ? true : false
      else
        item['v'] == @want['v']
      end
    end
  end
end
