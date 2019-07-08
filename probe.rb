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
        backscan options
      end

      if @items.size < @num
        begin
          @archive.probes.add self              # we will not get incoming events
          @mutex.synchronize do
            @condition_variable.wait(@mutex,options[:timeout])    # sleep until processing an item wakes us up
          end
        ensure
          @archive.probes.remove self
        end
      end
      out = @items[0..@num-1]
      return out, out.size
    end

    def done
    end

    def backscan options
      # use binary search to earliest item to consider
      from = (0..@archive.items.size).bsearch do |i|
        @archive.items[i][:timestamp] >= options[:earliest]
      end
      # then look at each item from that index and up, stopping if haave enough items
      from.upto(@archive.items.size) do |i|
        process @archive.items[i]
        break if @done
      end
    end

    def reset
      @mutex.synchronize do
        @items.clear
        @done = false
      end
    end

    def process item
      return if @done
      @mutex.synchronize do
        if matches? item
          @items << item
          if @num && @items.size >= @num
            @done = true
            @condition_variable.broadcast
          end
        end
      end
    end

    def matches? item
      return false if @options[:type] && (item[:message] == nil || (item[:message].type != @options[:type]))
      return false if @options[:with_message] && !(item[:direction] && item[:message])
      return false if @block && @block.call == false
      true
    end
  end
end