module RSMP

  # Base class for waiting for specific status or command responses, specified by
  # a list of queries. Queries are defined as an array of hashes, e.g
  # [
  #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"securityCode", "v"=>"1111"},
  #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"year", "v"=>"2020"},
  #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"month", "v"=>/\d+/}
  #  ]
  #
  # Note that queries can contain regex patterns for values, like /\d+/ in the example above.
  #
  # When an input messages is received it typically contains several items, eg:
  # [
  #   {"cCI"=>"M0104", "n"=>"month", "v"=>"9", "age"=>"recent"},
  #   {"cCI"=>"M0104", "n"=>"day", "v"=>"29", "age"=>"recent"},
  #   {"cCI"=>"M0104", "n"=>"hour", "v"=>"17", "age"=>"recent"}
  # ]
  #
  # Each input item is matched against each of the queries.
  # If a match is found, it's stored in the @results hash, with the query as the key,
  # and a mesage and status as the key. In the example above, this query:
  #
  # {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"month", "v"=>/\d+/}
  #
  # matches this input:
  #
  # {"cCI"=>"M0104", "n"=>"month", "v"=>"9", "age"=>"recent"}
  # 
  # And the result is stored as:
  # {
  #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"month", "v"=>/\d+/} =>
  #     { <StatusResponse message>, {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"month", "v"=>"9"} }
  # }
  #
  #
  class Matcher < Collector

    # Initialize with a list a wanted statuses
    def initialize proxy, want, options={}
      super proxy, options.merge( ingoing: true, outgoing: false)
      @queries = {}
      want.each do |query|
        @queries[query] = nil
      end
    end

    # Get the results, as a hash of queries => results
    def result
      @queries
    end

    # Get messages from results
    def messages
      @queries.map { |query,result| result[:message] }.uniq
    end

    # get items from results
    def items
      @queries.map { |query,result| result[:item] }.uniq
    end

    # Queries left to match?
    def done?
      @queries.values.all? { |result| result != nil }
    end

    # Mark a query as matched, by linking it to the matched item and message
    def keep query, message, item
      @queries[query] = { message:message, item:item }
    end

    # Mark a query as not matched
    def forget query
      @queries[query] = nil
    end

    # Check if a messages is wanted.
    # Returns true when we found all that we want.
    def check_match message
      return unless match?(message)
      @queries.keys.each do |query|        # look through queries
        get_items(message).each do |item|  # look through status items in message
          break if check_item_match message, query, item
        end
      end
    end

    # Check if an item matches, and mark query as matched/unmatched accordingly.
    def check_item_match message, query, item
      matched = match_item? query, item
      if matched == true
        keep query, message, item
        true
      elsif matched == false
        forget query
        true
      end
    end
  end

  # Class for waiting for specific command responses
  class CommandResponseMatcher < Matcher
    def initialize proxy, want, options={}
      super proxy, want, options.merge(
        type: ['CommandResponse','MessageNotAck'],
        title:'command request'
      )
    end

    def get_items message
      message.attributes['rvs']
    end

    # Match an item against a query
    def match_item? query, item
      return nil if query['cCI'] && query['cCI'] != item['cCI']
      return nil if query['n'] && query['n'] != item['n']
      if query['v'].is_a? Regexp
        return false if query['v'] && item['v'] !~ query['v']
      else
        return false if query['v'] && item['v'] != query['v']
      end
      true
    end
  end

  # Base class for waiting for status updates or responses
  class StatusUpdateOrResponseMatcher < Matcher
    def initialize proxy, want, options={}
      super proxy, want, options.merge
    end

    def get_items message
      message.attributes['sS']
    end

    # Match an item against a query
    def match_item? query, item
      return nil if query['sCI'] && query['sCI'] != item['sCI']
      return nil if query['cO'] && query['cO'] != item['cO']
      return nil if query['n'] && query['n'] != item['n']
      return false if query['q'] && query['q'] != item['q']
      if query['s'].is_a? Regexp
        return false if query['s'] && item['s'] !~ query['s']
      else
        return false if query['s'] && item['s'] != query['s']
      end
      true
    end
  end

  # Class for waiting for specific status responses
  class StatusResponseMatcher < StatusUpdateOrResponseMatcher
    def initialize proxy, want, options={}
      super proxy, want, options.merge(
        type: ['StatusResponse','MessageNotAck'],
        title: 'status request'
      )
    end
  end

  # Class for waiting for specific status responses
  class StatusUpdateMatcher < StatusUpdateOrResponseMatcher
    def initialize proxy, want, options={}
      super proxy, want, options.merge(
        type: ['StatusUpdate','MessageNotAck'],
        title:'status subscription'
      )
    end
  end

  # Class for waiting for an aggregated status response
  class AggregatedStatusMatcher < Collector
    def initialize proxy, options={}
      super proxy, options.merge(
        num: 1,
        type: ['AggregatedStatus','MessageNotAck'],
        title: 'aggregated status request'
      )
    end
  end
end
