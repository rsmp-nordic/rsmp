module RSMP
  # Collects messages from a distributor.
  # Can filter by message type, componet and direction.
  # Wakes up the once the desired number of messages has been collected.
  class Collector
    include Receiver
    include Status
    include Reporting
    include Logging

    attr_reader :condition, :messages, :status, :error, :task, :m_id

    def initialize(distributor, options = {})
      initialize_receiver distributor, filter: options[:filter]
      @options = {
        cancel: {
          schema_error: true,
          disconnect: false
        }
      }.deep_merge options
      @timeout = options[:timeout]
      @num = options[:num]
      @m_id = options[:m_id]
      @condition = Async::Notification.new
      make_title options[:title]

      if task
        @task = task
      elsif distributor.respond_to? 'task'
        # if distributor is a Proxy, or some other object that implements task(),
        # then try to get the task that way
        @task = distributor.task
      end
      reset
    end

    def make_title(title)
      @title = if title
                 title
               elsif @filter
                 [@filter.type].flatten.join('/')
               else
                 ''
               end
    end

    def use_task(task)
      @task = task
    end

    def reset
      @messages = []
      @error = nil
      @status = :ready
    end

    # Inspect formatter that shows the message we have collected
    def inspect
      "#<#{self.class.name}:#{object_id}, #{inspector(:@messages)}>"
    end

    # if an errors caused collection to abort, then raise it
    # return self, so this can be tucked on to calls that return a collector
    def ok!
      raise @error if @error

      self
    end

    # Collect message
    # Will return once all messages have been collected, or timeout is reached
    def collect(&)
      start(&)
      wait
      @status
    ensure
      @distributor&.remove_receiver self
    end

    # Collect message
    # Returns the collected messages, or raise an exception in case of a time out.
    def collect!(&)
      collect(&)
      ok!
      @messages
    end

    # If collection is not active, return status immeditatly. Otherwise wait until
    # the desired messages have been collected, or timeout is reached.
    def wait
      if collecting?
        if @timeout
          @task.with_timeout(@timeout) { @condition.wait }
        else
          @condition.wait
        end
      end
      @status
    rescue Async::TimeoutError
      @error = RSMP::TimeoutError.new describe_progress
      @status = :timeout
    end

    # If collection is not active, raise an error. Otherwise wait until
    # the desired messages have been collected.
    # If timeout is reached, an exceptioin is raised.
    def wait!
      wait
      raise @error if timeout?

      @messages
    end

    # Start collection and return immediately
    # You can later use wait() to wait for completion
    def start(&block)
      raise "Can't start collectimng unless ready (currently #{@status})" unless ready?

      @block = block
      raise ArgumentError, 'Num, timeout or block must be provided' unless @num || @timeout || @block

      reset
      @status = :collecting
      log_start
      @distributor&.add_receiver self
    end

    # Check if we receive a NotAck related to initiating request, identified by @m_id.
    def reject_not_ack(message)
      return unless @m_id

      return unless message.is_a?(MessageNotAck)
      return unless message.attribute('oMId') == @m_id

      m_id_short = RSMP::Message.shorten_m_id @m_id, 8
      cancel RSMP::MessageRejected.new("#{@title} #{m_id_short} was rejected with '#{message.attribute('rea')}'")
      @distributor.log "#{identifier}: cancelled due to a NotAck", level: :debug
      true
    end

    # Handle message and return true if we're done collecting
    def receive(message)
      raise ArgumentError unless message
      unless ready? || collecting?
        raise "can't process message when status is :#{@status}, title: #{@title}, desc: #{describe}"
      end

      if perform_match message
        if done?
          complete
        else
          incomplete
        end
      end
      @status
    end

    def describe; end

    # Match message against our collection criteria
    def perform_match(message)
      return false if reject_not_ack(message)
      return false unless acceptable?(message)

      if @block
        status = [@block.call(message)].flatten
        return unless collecting?

        keep message if status.include?(:keep)
      else
        keep message
      end
    end

    # Have we collected the required number of messages?
    def done?
      @num && @messages.size >= @num
    end

    # Called when we're done collecting. Remove ourself as a receiver,
    # se we don't receive message notifications anymore
    def complete
      @status = :ok
      do_stop
      log_complete
    end

    # called when we received a message, but are not done yet
    def incomplete
      log_incomplete
    end

    # Remove ourself as a receiver, so we don't receive message notifications anymore,
    # and wake up the async condition
    def do_stop
      @distributor.remove_receiver self
      @condition.signal
    end

    # Handle upstream error
    def receive_error(error, options = {})
      case error
      when RSMP::SchemaError
        receive_schema_error error, options
      when RSMP::DisconnectError
        receive_disconnect error, options
      end
    end

    # Cancel if we received e schema error for a message type we're collecting
    def receive_schema_error(error, options)
      return unless @options.dig(:cancel, :schema_error)

      message = options[:message]
      return unless message

      klass = message.class.name.split('::').last
      return unless @filter&.type.nil? || [@filter&.type].flatten.include?(klass)

      @distributor.log "#{identifier}: cancelled due to schema error in #{klass} #{message.m_id_short}", level: :debug
      cancel error
    end

    # Cancel if we received e notifiction about a disconnect
    def receive_disconnect(error, _options)
      return unless @options.dig(:cancel, :disconnect)

      @distributor.log "#{identifier}: cancelled due to a connection error: #{error}", level: :debug
      cancel error
    end

    # Abort collection
    def cancel(error = nil)
      @error = error
      @status = :cancelled
      do_stop
    end

    # Store a message in the result array
    def keep(message)
      @messages << message
    end

    # Check a message against our match criteria
    # Return true if there's a match, false if not
    def acceptable?(message)
      @filter.nil? || @filter.accept?(message)
    end
  end
end
