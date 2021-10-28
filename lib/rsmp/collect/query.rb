module RSMP
    
  # Class that matches a single status or command item
  class Query
    attr_reader :want, :got, :message

    def initialize want
      @want = want
      @got = nil
      @message = nil
      @done = false
    end

    # Are we done, i.e. did the last checked item match?
    def done?
      @done
    end

    # Check an item and set @done to true if it matches
    # Always store the item and corresponding message.
    def check_match item, message
      @message = message
      @got = item
      matched = match? item
      if matched != nil
        @done = matched
        true
      end
    end

    def match? item
    end
  end
end
