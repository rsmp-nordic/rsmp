module RSMP

  # Collects ingoing and/or outgoing messages from a notifier.
  # Can filter by message type and wakes up the client once the desired number of messages has been collected.
  class MessageCollector < Collector
    attr_reader :condition, :messages, :done

    def initialize proxy, options={}
      super proxy, options
      @options = {
        cancel: {
          schema_error: true,
          disconnect: false,
        }
      }.deep_merge options
      @ingoing = options[:ingoing] == nil ? true  : options[:ingoing]
      @outgoing = options[:outgoing] == nil ? false : options[:outgoing]
      @condition = Async::Notification.new
      @title = options[:title] || [@options[:type]].flatten.join('/')
      @options[:timeout] ||= 1
      @options[:num] ||= 1
      reset
    end

    # Inspect formatter that shows the message we have collected
    def inspect
      "#<#{self.class.name}:#{self.object_id}, #{inspector(:@messages)}>"
    end

    # Want ingoing messages?
    def ingoing?
      @ingoing == true
    end

    # Want outgoing messages?
    def outgoing?
      @outgoing == true
    end

    # Block until all messages have been collected
    def wait
      @condition.wait
    end

    # Collect message
    # Will block until all messages have been collected,
    # or we time out
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
      str = "#{@title.capitalize} collection"
      str << " in response to #{options[:m_id]}" if options[:m_id]
      str << " didn't complete within #{@options[:timeout]}s"
      reached = progress
      str << ", reached #{progress[:reached]}/#{progress[:need]}"
      raise RSMP::TimeoutError.new str
    end

    # Return progress as collected vs. number requested
    def progress
      need = @options[:num]
      reached =  @messages.size
      { need: need, got: reached }
    end

    # Get the collected message.
    def message
      @messages.first
    end

    # Get the collected messages.
    def messages
      @messages
    end

    # Clear all query results
    def reset
      @messages = []
      @error = nil
      @done = false
    end

    # Check if we receive a NotAck related to initiating request, identified by @m_id.
    def check_not_ack message
      return unless @options[:m_id]
      if message.is_a?(MessageNotAck)
        if message.attribute('oMId') == @options[:m_id]
          m_id_short = RSMP::Message.shorten_m_id @options[:m_id], 8
          @error = RSMP::MessageRejected.new("#{@title} #{m_id_short} was rejected with '#{message.attribute('rea')}'")
          complete
        end
        false
      end
    end

    # Handle message. and return true when we're done collecting
    def notify message
      raise ArgumentError unless message
      raise RuntimeError.new("can't process message when already done") if @done
      check_not_ack(message)
      return true if @done
      perform_match message
      complete if done?
      @done
    end

    # Match message against our collection criteria
    def perform_match message
      matched = type_match?(message) && block_match?(message)
      if matched == true
        keep message
      elsif matched == false
        forget message
      end
    end

    # Have we collected the required number of messages?
    def done?
      @options[:num] && @messages.size >= @options[:num]
    end

    # Called when we're done collecting. Remove ourself as a listener,
    # se we don't receive message notifications anymore
    def complete
      @done = true
      @proxy.remove_listener self
      @condition.signal
    end

    # The proxy experienced some error.
    # Check if this should cause us to cancel.
    def notify_error error, options={}
      case error
      when RSMP::SchemaError
        notify_schema_error error, options
      when RSMP::ConnectionError
        notify_disconnect error, options
      end
    end

    # Cancel if we received e schema error for a message type we're collecting
    def notify_schema_error error, options
      return unless @options.dig(:cancel,:schema_error)
      message = options[:message]
      return unless message
      klass = message.class.name.split('::').last
      return unless [@options[:type]].flatten.include? klass
      @proxy.log "Collect cancelled due to schema error in #{klass} #{message.m_id_short}", level: :debug
      cancel error
    end

    # Cancel if we received e notificaiton about a disconnect
    def notify_disconnect error, options
      return unless @options.dig(:cancel,:disconnect)
      @proxy.log "Collect cancelled due to a connection error: #{error.to_s}", level: :debug
      cancel error
    end

    # Abort collection
    def cancel error
      @error = error if error
      @done = false
      @proxy.remove_listener self
      @condition.signal
    end

    # Store a message in the result array
    def keep message
      @messages << message
    end

    # Remove a message from the result array
    def forget message
      @messages.delete message
    end

    # Check a message against our match criteria
    # Return true if there's a match, false if not
    def type_match? message
      return false if message.direction == :in && @ingoing == false
      return false if message.direction == :out && @outgoing == false
      if @options[:type]
        if @options[:type].is_a? Array
          return false unless @options[:type].include? message.type
        else
          return false unless message.type == @options[:type]
        end
      end
      if @options[:component]
        return false if message.attributes['cId'] && message.attributes['cId'] != @options[:component]
      end
      true
    end
  end

  def block_match? message
    @block.call(message) == true
  end
end