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
    # Store the item and corresponding message if there's a positive or negative match
    def check_match item, message
      matched = match? item
      if matched != nil
        @message = message
        @got = item
        @done = matched
      end
      matched
    end

    def match? item
    end
  end
end
