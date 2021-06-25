# Collects matching ingoing and/or outgoing messages and
# wakes up the client once the desired amount has been collected.
# Can listen for ingoing and/or outgoing messages.

module RSMP
  class Collector < Listener

    attr_reader :condition, :messages, :done

    def initialize proxy, options={}
      super proxy, options
      @ingoing = options[:ingoing] == nil ? true  : options[:ingoing]
      @outgoing = options[:outgoing] == nil ? false : options[:outgoing]
      @messages = []
      @condition = Async::Notification.new
      @done = false
      @options = options
      @num = options[:num]
    end

    def inspect
      "#<#{self.class.name}:#{self.object_id}, #{inspector(:@messages)}>"
    end

    def ingoing?
      @ingoing == true
    end

    def outgoing?
      @outgoing == true
    end

    def wait
      @condition.wait
    end

    def collect_for task, duration
      siphon do
        task.sleep duration
      end
    end

    def collect task, options={}, &block
      @num = options[:num] if options[:num]
      @options[:timeout] = options[:timeout] if options[:timeout]
      @block = block

      unless @done
        listen do
          task.with_timeout(@options[:timeout]) do
            @condition.wait
          end
        end
      end

      if @num == 1
        @messages = @messages.first       # if one message was requested, return it instead of array
      else
        @messages = @messages.first @num  # return array, but ensure we never return more than requested
      end
      @messages
    end

    def reset
      @message.clear
      @done = false
    end

    def notify message
      raise ArgumentError unless message
      return true if @done
      return if message.direction == :in && @ingoing == false
      return if message.direction == :out && @outgoing == false
      if matches? message
        @messages << message
        if @num && @messages.size >= @num
          @done = true
          @proxy.remove_listener self
          @condition.signal
        end
      end
    end

    def matches? message
      raise ArgumentError unless message

      if @options[:type]
        return false if message == nil
        if @options[:type].is_a? Array
          return false unless @options[:type].include? message.type
        else
          return false unless message.type == @options[:type]
        end
      end
      if @options[:component]
        return false if message.attributes['cId'] && message.attributes['cId'] != @options[:component]
      end
      if @block
        return false if @block.call(message) == false
      end
      true
    end
  end
end