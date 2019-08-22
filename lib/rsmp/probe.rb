# A probe checks incoming messages and store matches
# Once it has collected what it needs, it triggers a condition variable
# and the client wakes up.

module RSMP
  class Probe
    attr_reader :condition, :items, :done

    # block should send a message and return message just sent
    def self.collect_response connector, options={}, &block
      from = connector.archive.current_index
      sent = yield
      raise RuntimeError unless sent && sent[:message].is_a?(RSMP::Message)
      item = connector.archive.capture(options.merge(from: from+1, num: 1, with_message: true)) do |item|
        ["CommandResponse","StatusResponse","MessageNotAck"].include?(item[:message].type)
      end
      if item
        item[:message] 
      else
        nil
      end
    end


    def initialize archive
      raise ArgumentError.new("Archive expected") unless archive.is_a? Archive
      @archive = archive
      @items = []
      @condition = Async::Notification.new
    end

    def capture task, options={}, &block
      @options = options
      @block = block
      @num = options[:num]

      if options[:earliest]
        from = find_timestamp_index options[:earliest]
        backscan from
      elsif options[:from]
        backscan options[:from]
      end

      # if backscan didn't find enough items, then
      # insert ourself as probe and sleep until enough items are captured
      if @items.size < @num
        begin
          @archive.probes.add self
          task.with_timeout(options[:timeout]) do
            @condition.wait
          end
        ensure
          @archive.probes.remove self
        end
      end

      if @num == 1
        @items.first        # if one item was requested, return item instead of array
      else
        @items[0..@num-1]   # return array, but ensure we never return more than requested
      end
    end

    def find_timestamp_index earliest
      (0..@archive.items.size).bsearch do |i|        # use binary search to find item index
        @archive.items[i][:timestamp] >= earliest
      end
    end

    def backscan from
      from.upto(@archive.items.size-1) do |i|
        return if process @archive.items[i]
      end
    end

    def reset
      @items.clear
      @done = false
    end

    def process item
      raise ArgumentError unless item
      return true if @done
      if matches? item
        @items << item
        if @num && @items.size >= @num
          @done = true
          @condition.signal
          return true
        end
      end
      false
    end

    def matches? item
      raise ArgumentError unless item
      return false if @options[:type] && (item[:message] == nil || (item[:message].type != @options[:type]))
      return false if @options[:with_message] && !(item[:direction] && item[:message])
      return false if @block && @block.call(item) == false
      true
    end
  end
end