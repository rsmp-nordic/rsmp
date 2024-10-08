module RSMP
  # Base class for waiting for specific status or command responses, specified by
  # a list of matchers. Matchers are defined as an array of hashes, e.g
  # [
  #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"securityCode", "v"=>"1111"},
  #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"year", "v"=>"2020"},
  #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"month", "v"=>/\d+/}
  #  ]
  #
  # Note that matchers can contain regex patterns for values, like /\d+/ in the example above.
  #
  # When an input messages is received it typically contains several items, eg:
  # [
  #   {"cCI"=>"M0104", "n"=>"month", "v"=>"9", "age"=>"recent"},
  #   {"cCI"=>"M0104", "n"=>"day", "v"=>"29", "age"=>"recent"},
  #   {"cCI"=>"M0104", "n"=>"hour", "v"=>"17", "age"=>"recent"}
  # ]
  #
  # Each input item is matched against each of the matchers.
  # If a match is found, it's stored in the @results hash, with the matcher as the key,
  # and a mesage and status as the key. In the example above, this matcher:
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
    attr_reader :matchers

    # Initialize with a list of wanted statuses
    def initialize proxy, want, options={}
      raise ArgumentError.new("num option cannot be used") if options[:num]
      super proxy, options
      @matchers = want.map { |item| build_matcher item }
    end

    # Build a matcher object.
    # Sub-classes should override to use their own matcher classes.
    def build_matcher want
      Matcher.new want
    end

    # Get a results
    def matcher_result want
      matcher = @matchers.find { |q| q.want == want}
      raise unless matcher
      matcher.got
    end

    # Get an array of the last item received for each matcher
    def reached
      @matchers.map { |matcher| matcher.got }.compact
    end

    # Get messages from results
    def messages
      @matchers.map { |matcher| matcher.message }.uniq.compact
    end

    # Return progress as completes matchers vs. total number of matchers
    def progress
      need = @matchers.size
      reached =  @matchers.count { |matcher| matcher.done? }
      { need: need, reached: reached }
    end

    # Are there matchers left to type_match?
    def done?
      @matchers.all? { |matcher| matcher.done? }
    end

    # Get a simplified hash of matchers, with values set to either true or false,
    # indicating which matchers have been matched.
    def matcher_status
      @matchers.map { |matcher| [matcher.want, matcher.done?] }.to_h
    end

    # Get a simply array of bools, showing which matchers have been matched.
    def summary
      @matchers.map { |matcher| matcher.done? }
    end

    # Check if a messages matches our criteria.
    # Match each matcher against each item in the message
    def perform_match message
      return false if super(message) == false
      return unless collecting?
      @matchers.each do |matcher|       # look through matchers
        get_items(message).each do |item|  # look through items in message
          matched = matcher.perform_match(item,message,@block)
          return unless collecting?
          if matched != nil
            type = {true=>'match',false=>'mismatch'}[matched]
            @distributor.log "#{@title.capitalize} #{message.m_id_short} collect #{type} #{matcher.want}, item #{item}", level: :debug
            if matched == true
              matcher.keep message, item
            elsif matched == false
              matcher.forget
            end
          end
        end
      end
    end

    # don't collect anything. Matcher will collect them instead
    def keep message
    end

    def describe
      @matchers.map {|q| q.want.to_s }
    end

    # return a string that describes the attributes that we're looking for
    def describe_matcher
      "#{super} matching #{matcher_want_hash.to_s}"
    end

    # return a hash that describe the status of all matchers
    def progress_hash
      h = {}
      @matchers.each do |matcher|
        want = matcher.want
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
          if matcher.got && matcher.got['s']
            h[sCI][n] = { {s=>matcher.got['s']} => matcher.done? }
          else
            h[sCI][n] = { s=>nil }
          end
        end
      end
      h
    end

    # return a string that describe how many many messages have been collected
    def describe_progress
      num_matchers = @matchers.size
      num_matched =  @matchers.count { |matcher| matcher.done? }
      ".. Matched #{num_matched}/#{num_matchers} with #{progress_hash.to_s}"
    end

    def matcher_want_hash
      h = {}
      @matchers.each do |matcher|
        item = matcher.want
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
    def matcher_got_hash
      h = {}
      @matchers.each do |matcher|
        want = matcher.want
        got = matcher.got
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
      @distributor.log "#{identifier}: Completed with #{matcher_got_hash.to_s}", level: :collect
    end
  end
end
