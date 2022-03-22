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
  class StateCollector < Collector
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
      @queries.map { |query| query.message }.uniq.compact
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
      return false if super(message) == false
      return unless collecting?
      @queries.each do |query|       # look through queries
        get_items(message).each do |item|  # look through items in message
          matched = query.perform_match(item,message,@block)
          return unless collecting?
          if matched != nil
            #type = {true=>'match',false=>'mismatch'}[matched]
            #@notifier.log "#{@title.capitalize} #{message.m_id_short} collect #{type} #{query.want}, item #{item}", level: :debug
            if matched == true
              query.keep message, item
            elsif matched == false
              query.forget
            end
          end
        end
      end
    end

    # don't collect anything. Query will collect them instead
    def keep message
    end

    def describe
      @queries.map {|q| q.want.to_s }
    end

    # return a string that describes the attributes that we're looking for
    def describe_query
      "#{super} matching #{query_want_hash.to_s}"
    end

    # return a hash that describe the status of all queries
    def progress_hash
      h = {}
      @queries.each do |query|
        want = query.want
        if want['cCI']
          cCI = want['cCI']
          h[cCI] ||= {}
          cO = h['cO']
          n = h['n']
          v = h['v']
          h[cCI][cO] ||= {}
          h[cCI][cO][n] = v
        elsif want['sCI']
          sCI = want['sCI']
          h[sCI] ||= {}
          n = want['n']
          s = want['s']
          if query.got && query.got['s']
            h[sCI][n] = { {s=>query.got['s']} => query.done? }
          else
            h[sCI][n] = { s=>nil }
          end
        end
      end
      h
    end

    # return a string that describe how many many messages have been collected
    def describe_progress
      num_queries = @queries.size
      num_matched =  @queries.count { |query| query.done? }
      ".. Matched #{num_matched}/#{num_queries} with #{progress_hash.to_s}"
    end

    def query_want_hash
      h = {}
      @queries.each do |query|
        item = query.want
        if item['cCI']
          cCI = item['cCI']
          h[cCI] ||= {}
          cO = item['cO']
          h[cCI][cO] ||= {}
          n = item['n']
          v = item['v']
          h[cCI][cO][n] = v || :any
        elsif item['sCI']
          sCI = item['sCI']
          h[sCI] ||= {}
          n = item['n']
          s = item['s']
          h[sCI][n] = s || :any
        end
      end
      h
    end

    # return a hash that describe the end result
    def query_got_hash
      h = {}
      @queries.each do |query|
        want = query.want
        got = query.got
        if want['cCI']
          cCI = want['cCI']
          h[cCI] ||= {}
          cO = want['cO']
          h[cCI][cO] ||= {}
          n = want['n']
          v = got ? got['v'] : nil
          h[cCI][cO][n] = v
        elsif want['sCI']
          sCI = want['sCI']
          h[sCI] ||= {}
          n = want['n']
          s = got ? got['s'] : nil
          h[sCI][n] = s
        end
      end
      h
    end

    # log when we end collecting
    def log_complete
      @notifier.log "#{identifier}: Completed with #{query_got_hash.to_s}", level: :collect
    end
  end
end
