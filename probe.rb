# A probe checks incoming messages and store matches
# Once it has collected what it needs, it triggers a condition variable
# and the client wakes up.

module RSMP
  class Probe
    attr_reader :condition_variable, :items, :done

    def initialize options=nil, &block
      @items = []
      @mutex = Mutex.new
      @condition_variable = ConditionVariable.new
      @options = options
      @block = block
      @done = false
    end

    def capture num, timeout, options={}
      @num = num
      if options[:archive]
        backscan options[:archive], options[:earliest]
      end
      if @items.size < @num
        @mutex.synchronize do
          @condition_variable.wait(@mutex,timeout)
        end
      end
      out = @items[0..num-1]
      return out, out.size
    end

    def backscan archive, earliest
      items = []
      archive.items.reverse_each do |item|
        break if earliest && item.timestamp < earliest
        items.unshift item
      end
      items.each { |item| process item }
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
      if @options
        return false if @options[:type] && (item[:message] == nil || (item[:message].type != @options[:type]))
        return false if @options[:with_message] && !(item[:direction] && item[:message])
      end
      return false if @block && @block.call == false
      true
    end
  end
end