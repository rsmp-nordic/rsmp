# A probe checks incoming messages and store matches
# Once it has collected what it needs, it triggers a condition variable
# and the client wakes up.

<<-EOF

global archive
local archive is not needed, we can just scan the global archive with a time range
create a probe and insert it. it will backscan a range, and then process incoming messages one by one
once it's done it should remove itself


EOF


module RSMP
  class Probe
    attr_reader :condition_variable, :items, :done

    def initialize archive
      raise ArgumentError.new("Archive expected") unless archive.is_a? Archive
      @archive = archive
      @items = []
      @mutex = Mutex.new
      @condition_variable = ConditionVariable.new
    end

    def capture options={}, &block
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
          @mutex.synchronize do
            @condition_variable.wait(@mutex,options[:timeout])
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
      @mutex.synchronize do
        @items.clear
        @done = false
      end
    end

    def process item
      raise ArgumentError unless item
      return true if @done
      @mutex.synchronize do
        if matches? item
          @items << item
          if @num && @items.size >= @num
            @done = true
            @condition_variable.broadcast
            return true
          end
        end
      end
      false
    end

    def matches? item
      raise ArgumentError unless item
      return false if @options[:type] && (item[:message] == nil || (item[:message].type != @options[:type]))
      return false if @options[:with_message] && !(item[:direction] && item[:message])
      return false if @block && @block.call == false
      true
    end
  end
end