module RSMP
    
  # Class that matches a single status or command item
  class Query
    attr_reader :want, :item, :message

    def initialize want
      @want = want
      @item = nil
      @message = nil
      @done = false
    end

    def done?
      @done
    end

    def check_match item, message
      matched = match? item
      if matched == true
        keep message, item
        true
      elsif matched == false
        forget
        true
      end
    end

    def match? item
    end

    # Mark a query as matched and store item and message
    def keep message, item
      @message = message
      @item = item
      @done = true
    end

    # Mark a query as not matched
    def forget
      @done = false
    end
  end
end
