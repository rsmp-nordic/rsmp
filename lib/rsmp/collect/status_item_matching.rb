module RSMP
  # Shared identity matching for status values and subscription items.
  module StatusItemMatching
    def match_code(item)
      return nil if @want['sCI'] && @want['sCI'] != item['sCI']
      return nil if @want['cO'] && @want['cO'] != item['cO']
      return nil if @want['n'] && @want['n'] != item['n']

      true
    end

    def match(item)
      return nil unless match_code(item)

      match_value?(item)
    end
  end
end
