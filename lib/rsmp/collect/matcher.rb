module RSMP
  # Class that matches a single status or command item
  class Matcher
    attr_reader :want, :got, :message

    def initialize(want)
      @want = want
      @got = nil
      @message = nil
    end

    # Are we done, i.e. did the last checked item match?
    def done?
      @got != nil
    end

    # Check an item and set @done to true if it matches
    # Store the item and corresponding message if there's a positive or negative match
    def perform_match(item, _message, block)
      matched = match? item
      if !matched.nil? && block
        status = block.call(nil, item)
        matched = status if [true, false].include?(status)
      end
      matched
    end

    def keep(message, item)
      @message = message
      @got = item
    end

    def forget
      @message = nil
      @got = nil
    end

    def match?(item); end
  end
end
