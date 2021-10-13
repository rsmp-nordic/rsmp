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

    def collect task, options={}, &block
      @options.merge! options
      @block = block

      unless @done
        listen do
          task.with_timeout(@options[:timeout]) do
            @condition.wait
          end
        end
      end
      result
    end

    def result
      return @messages.first if @options[:num] == 1      # if one message was requested, return it instead of array
      @messages.first @options[:num]  # return array, but ensure we never return more than requested
    end

    def reset
      @message.clear
      @done = false
    end

    def notify message
      raise ArgumentError unless message
      return true if @done
      if matches? message
        keep message
        if done?
          complete 
          true
        end
      end
    end

    def done?
      @options[:num] && @messages.size >= @options[:num]
    end

    def complete
      @done = true
      @proxy.remove_listener self
      @condition.signal
    end

    def keep message
      @messages << message
    end

    def matches? message
      raise ArgumentError unless message

      return if message.direction == :in && @ingoing == false
      return if message.direction == :out && @outgoing == false

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