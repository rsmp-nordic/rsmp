module RSMP
  # Match a specific status response or update
  class StatusMatcher < Matcher
    # Match a status value against a matcher
    def match?(item)
      return unless matches_value?(item, 'sCI')
      return unless matches_value?(item, 'cO')
      return unless matches_value?(item, 'n')
      return false unless matches_quality?(item)
      return false unless matches_status?(item)

      true
    end

    private

    def matches_value?(item, key)
      wanted = @want[key]
      return true unless wanted

      wanted == item[key]
    end

    def matches_quality?(item)
      wanted = @want['q']
      return true unless wanted

      wanted == item['q']
    end

    def matches_status?(item)
      wanted = @want['s']
      return true unless wanted

      return !!(item['s'] =~ wanted) if wanted.is_a?(Regexp)

      item['s'] == wanted
    end
  end
end
