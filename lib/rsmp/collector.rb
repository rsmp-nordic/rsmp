module RSMP

  # Collects ingoing and/or outgoing messages.
  # Can filter by message type and wakes up the client once the desired number of messages has been collected.
  class Collector < Listener
    attr_reader :condition, :messages, :done

    def initialize proxy, options={}
      raise unless options[:timeout]
      super proxy, options
      @options = options
      @ingoing = options[:ingoing] == nil ? true  : options[:ingoing]
      @outgoing = options[:outgoing] == nil ? false : options[:outgoing]
      @condition = Async::Notification.new
      @title = options[:title] || [@options[:type]].flatten.join('/')
      reset
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
      return @error if @error
      self
    rescue Async::TimeoutError
      str = "Did not receive #{@title}"
      str << " in response to #{options[:m_id]}" if options[:m_id]
      str << " within #{options[:timeout]}s"
      raise RSMP::TimeoutError.new str
    end

    def result
      return @messages.first if @options[:num] == 1      # if one message was requested, return it instead of array
      @messages.first @options[:num]      # return array, but ensure we never return more than requested
    end

    def reset
      @messages = []
      @error = nil
      @done = false
    end

    # Check for MessageNotAck
    # If the original request identified by @m_id is rejected, set the result to an exception,
    # which will be returned by the async task and stored as the task result.
    # When the parent task call wait() on the task, the exception will be raised in the parent task.
    def check_not_ack message
      return unless @options[:m_id]
      if message.is_a?(MessageNotAck)
        if message.attribute('oMId') == @options[:m_id]
          m_id_short = RSMP::Message.shorten_m_id @options[:m_id], 8
          @error = RSMP::MessageRejected.new("#{@title} #{m_id_short} was rejected: #{message.attribute('rea')}")
          complete
        end
        false
      end
    end

    # Handle message. and return true when we're done collecting
    def notify message
      raise ArgumentError unless message
      check_not_ack(message)
      return true if @done
      check_match message
      complete if done?
      @done
    end

    # Match message against our collection criteria
    def check_match message
      matched = match? message
      if matched == true
        keep message
      elsif matched == false
        forget message
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

    def forget message
      @messages.delete message
    end

    def match? message
      raise ArgumentError unless message
      return if message.direction == :in && @ingoing == false
      return if message.direction == :out && @outgoing == false
      if @options[:type]
        return if message == nil
        if @options[:type].is_a? Array
          return unless @options[:type].include? message.type
        else
          return unless message.type == @options[:type]
        end
      end
      if @options[:component]
        return if message.attributes['cId'] && message.attributes['cId'] != @options[:component]
      end
      if @block
        return if @block.call(message) == false
      end
      true
    end
  end
end