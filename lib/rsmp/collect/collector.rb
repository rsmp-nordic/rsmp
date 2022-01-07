module RSMP

  # Collects ingoing and/or outgoing messages from a notifier.
  # Can filter by message type and wakes up the client once the desired number of messages has been collected.
  class Collector < Listener
    attr_reader :condition, :messages, :status, :error

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
      reset
    end

    # Clear all query results
    def reset
      @messages = []
      @error = nil
      @status = :ready
      @why = nil
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

    # If collection is complete, return immeditatly. Otherwise wait until
    # the desired messages have been collected, or timeout is reached.
    def wait task
      wait! task
    rescue RSMP::TimeoutError
      @status
    end

    # If collection is complete, return immeditatly. Otherwise wait until
    # the desired messages have been collected.
    # If timeout is reached, an exceptioin is raised.
    def wait! task
      return @status unless @status == :collecting
      if @options[:timeout]
        task.with_timeout(@options[:timeout]) { @condition.wait }
      else
        @condition.wait
      end
      @status
    rescue Async::TimeoutError
      @status = :timeout
      raise RSMP::TimeoutError.new(describe_progress)
    end

    # Start collection and return immediately
    # You can later use wait() to wait for completion
    def start &block
      raise RuntimeError.new("Can't begin unless ready (currenty #{@status})") unless @status == :ready
      @block = block
      raise ArgumentError.new("Num, timeout or block must be provided") unless @options[:num] || @options[:timeout] || @block
      reset
      @status = :collecting
      @notifier.add_listener self if @notifier
    end

    # Collect message
    # Will return once all messages have been collected, or timeout is reached
    def collect task, &block
      start &block
      wait task
      @status
    ensure
      @notifier.remove_listener self
    end

    # Build a string describing how how progress reached before timeout
    def describe_progress
      str = "#{@title.capitalize} collection "
      str << "in response to #{@options[:m_id]} " if @options[:m_id]
      str << "didn't complete within #{@options[:timeout]}s, "
      str << "reached #{@messages.size}/#{@options[:num]}"
      str
    end

    # Collect message
    # Returns the collected messages, or raise an exception in case of a time out.
    def collect! task, &block
      case collect(task, &block)
      when :timeout
        raise RSMP::TimeoutError.new @why
      else
        @messages
      end
    end

    # Check if we receive a NotAck related to initiating request, identified by @m_id.
    def reject_not_ack message
      return unless @options[:m_id]
      if message.is_a?(MessageNotAck)
        if message.attribute('oMId') == @options[:m_id]
          m_id_short = RSMP::Message.shorten_m_id @options[:m_id], 8
          cancel RSMP::MessageRejected.new("#{@title} #{m_id_short} was rejected with '#{message.attribute('rea')}'")
          true
        end
      end
    end

    # Handle message. and return true when we're done collecting
    def notify message
      raise ArgumentError unless message
      raise RuntimeError.new("can't process message when done") unless @status == :ready || @status == :collecting
      unless reject_not_ack(message)
        perform_match message
      end
      @status
    end

    # Match message against our collection criteria
    def perform_match message
      return unless type_match?(message)
      if @block
        status = [@block.call(message)].flatten
        keep message if status.include?(:keep)
        if status.include?(:cancel)
          cancel('Cancelled by block')
        else
          complete if done?
        end
      else
        keep message
        complete if done?
      end
    end

    # Have we collected the required number of messages?
    def done?
      @options[:num] && @messages.size >= @options[:num]
    end

    # Called when we're done collecting. Remove ourself as a listener,
    # se we don't receive message notifications anymore
    def complete
      @status = :ok
      do_stop
    end

    # Remove ourself as a listener, so we don't receive message notifications anymore,
    # and wake up the async condition
    def do_stop
      @notifier.remove_listener self
      @condition.signal
    end

    # The proxy experienced some error.
    # Check if this should cause us to cancel.
    def notify_error error, options={}
      case error
      when RSMP::SchemaError
        notify_schema_error error, options
      when RSMP::DisconnectError
        notify_disconnect error, options
      end
    end

    # Cancel if we received e schema error for a message type we're collecting
    def notify_schema_error error, options
      return unless @options.dig(:cancel,:schema_error)
      message = options[:message]
      return unless message
      klass = message.class.name.split('::').last
      return unless @options[:type] == nil || [@options[:type]].flatten.include?(klass)
      @notifier.log "Collection cancelled due to schema error in #{klass} #{message.m_id_short}", level: :debug
      cancel error
    end

    # Cancel if we received e notificaiton about a disconnect
    def notify_disconnect error, options
      return unless @options.dig(:cancel,:disconnect)
      @notifier.log "Collection cancelled due to a connection error: #{error.to_s}", level: :debug
      cancel error
    end

    # Abort collection
    def cancel error
      @error = error
      @status = :cancelled
      do_stop
    end

    # Store a message in the result array
    def keep message
      @messages << message
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
end