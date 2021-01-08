# A probe checks incoming messages and store matches
# Once it has collected what it needs, it triggers a condition variable
# and the client wakes up.

module RSMP
  class Collector < Receiver
    attr_reader :condition, :items, :done

    def initialize proxy, options={}
      #raise ArgumentError.new("timeout option is missing") unless options[:timeout]
      super proxy
      @items = []
      @condition = Async::Notification.new
      @done = false
      @options = options
      @num = options[:num]
    end

    def wait
      @condition.wait
    end

    def collect_for task, duration
      siphon do
        task.sleep duration
      end
    end

    def collect task, &block
      @block = block

      siphon do
        task.with_timeout(@options[:timeout]) do
          @condition.wait
        end
      end

      #if @num == 1
      #  @items = @items.first       # if one item was requested, return item instead of array
      #else
      #  @items = @items.first @num  # return array, but ensure we never return more than requested
      #end
      #@items
    end

    def reset
      @items.clear
      @done = false
    end

    def receive item
      raise ArgumentError unless item
      return true if @done
      if matches? item
        @items << item
        if @num && @items.size >= @num
          @done = true
          @proxy.remove_receiver self
          @condition.signal
        end
      end
    end

    def matches? item
      raise ArgumentError unless item

      if @options[:type]
        return false if item[:message] == nil
        if @options[:type].is_a? Array
          return false unless @options[:type].include? item[:message].type
        else
          return false unless item[:message].type == @options[:type]
        end
      end
      return if @options[:level] && item[:level] != @options[:level]
      return false if @options[:with_message] && !(item[:direction] && item[:message])
      if @options[:component]
        return false if item[:message].attributes['cId'] && item[:message].attributes['cId'] != @options[:component]
      end
      if @block
        return false if @block.call(item) == false
      end
      true
    end
  end
end