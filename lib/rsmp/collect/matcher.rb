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

    # Initialize with a list of wanted statuses
    def initialize proxy, want, options={}
      raise ArgumentError.new("num option cannot be used") if options[:num]
      super proxy, options.merge( ingoing: true, outgoing: false)
      @queries = want.map { |item| build_query item }
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
      query.got
    end

    # Get an array of the last item received for each query
    def reached
      @queries.map { |query| query.got }.compact
    end

    # Get messages from results
    def messages
      @queries.map { |query| query.message }.uniq
    end

    # Return progress as completes queries vs. total number of queries
    def progress
      need = @queries.size
      reached =  @queries.count { |query| query.done? }
      { need: need, reached: reached }
    end

    # Are there queries left to type_match?
    def done?
      @queries.all? { |query| query.done? }
    end

    # Get a simplified hash of queries, with values set to either true or false,
    # indicating which queries have been matched.
    def query_status
      @queries.map { |query| [query.want, query.done?] }.to_h
    end

    # Get a simply array of bools, showing which queries have been matched.
    def summary
      @queries.map { |query| query.done? }
    end

    # Check if a messages matches our criteria.
    # Match each query against each item in the message
    def perform_match message
      return unless type_match?(message)
      @queries.each do |query|       # look through queries
        get_items(message).each do |item|  # look through items in message
          matched = query.perform_match(item,message)
          if matched == true
            matched = @block.call(message,item) if @block
          end
          if matched != nil
            type = {true=>'match',false=>'mismatch'}[matched]
            @notifier.log "#{@title.capitalize} #{message.m_id_short} collect #{type} #{query.want}, item #{item}", level: :debug
            break
          end
        end
      end
      complete if done?
      @notifier.log "#{@title.capitalize} collect reached #{summary}", level: :debug
    end
  end
end
