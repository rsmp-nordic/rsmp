module RSMP
  # Match a specific command responses
  class CommandQuery < Query
    # Match a return value item against a query
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

  # Match a specific status response or update 
  class StatusQuery < Query
    # Match a status value against a query
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