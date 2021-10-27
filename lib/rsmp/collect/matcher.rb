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

  class Matcher < Collector
    attr_reader :queries

    # Initialize with a list a wanted statuses
    def initialize proxy, want, options={}
      super proxy, options.merge( ingoing: true, outgoing: false)
      @queries = want.map { |wanted_item| build_query wanted_item }
    end

    # Build a query object.
    # Sub-classes should override to use their own query classes.
    def build_query want
      Query.new want
    end

    # Get a results
    def query_result want
      query = @queries.find { |q| q.want == want}
      raise unless query
      query.item
    end

    # get the first message. Useful when you only collected one mesage
    def message
      @queries.first.message
    end

    # Get messages from results
    def messages
      @queries.map { |query| query.message }.uniq
    end

    # Get items from results
    def items
      @queries.map { |query| query.item }.uniq
    end

    # Are there queries left to match?
    def done?
      @queries.all? { |query| query.done? }
    end

    # Get a simplified hash of queries, with values set to either true or false,
    # indicating which queries have been matched.
    def status
      @queries.map { |query| [query.query,query.done?] }.to_h
    end

    # Get a simply array of bools, showing which queries ahve been matched.
    def summary
      @queries.map { |query| query.done? }
    end

    # Check if a messages matches our criteria.
    # We iterate through each of the status items or return values in the message
    # Breaks as soon as where done matching all queries
    def check_match message
      return unless match?(message)
      @queries.each do |query|       # look through queries
        get_items(message).each do |item|  # look through status items in message
          break if query.check_match(item,message) != nil #check_item_match message, query, item
        end
      end
    end
  end
end
