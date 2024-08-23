module RSMP

  # Collects messages from a distributor.
  # Can filter by message type, componet and direction.
  # Wakes up the once the desired number of messages has been collected.
  class Collector
    include Receiver
    attr_reader :condition, :messages, :status, :error, :task, :m_id

    def initialize distributor, options={}
      initialize_receiver distributor, filter: options[:filter]
      @options = {
        cancel: {
          schema_error: true,
          disconnect: false,
        }
      }.deep_merge options
      @timeout = options[:timeout]
      @num = options[:num]
      @m_id = options[:m_id]
      @condition = Async::Notification.new
      make_title options[:title]
      
      if task
        @task = task
      else
         # if distributor is a Proxy, or some other object that implements task(),
         # then try to get the task that way
        if distributor.respond_to? 'task'
          @task = distributor.task
        end
      end
      reset
    end

    def make_title title
      if title
        @title = title
      elsif @filter
        @title = [@filter.type].flatten.join('/')
      else
        @title = ""
      end
    end

    def use_task task
      @task = task
    end

    # Clear all matcher results
    def reset
      @messages = []
      @error = nil
      @status = :ready
    end

    # Inspect formatter that shows the message we have collected
    def inspect
      "#<#{self.class.name}:#{self.object_id}, #{inspector(:@messages)}>"
    end

    # Is collection active?
    def collecting?
      @status == :collecting
    end

    # Is collection complete?
    def ok?
      @status == :ok
    end

    # Has collection timed out?
    def timeout?
      @status == :timeout
    end

    # Is collection ready to start?
    def ready?
      @status == :ready
    end

    # Has collection been cancelled?
    def cancelled?
      @status == :cancelled
    end

    # Want ingoing messages?
    def ingoing?
      @ingoing == true
    end

    # Want outgoing messages?
    def outgoing?
      @outgoing == true
    end

    # if an errors caused collection to abort, then raise it
    # return self, so this can be tucked on to calls that return a collector
    def ok!
      raise @error if @error
      self
    end

    # Collect message
    # Will return once all messages have been collected, or timeout is reached
    def collect &block
      start &block
      wait
      @status
    ensure
      @distributor.remove_receiver self if @distributor
    end

    # Collect message
    # Returns the collected messages, or raise an exception in case of a time out.
    def collect! &block
      collect(&block)
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
    def start &block
      raise RuntimeError.new("Can't start collectimng unless ready (currently #{@status})") unless ready?
      @block = block
      raise ArgumentError.new("Num, timeout or block must be provided") unless @num || @timeout || @block
      reset
      @status = :collecting
      log_start
      @distributor.add_receiver self if @distributor
    end

    # Build a string describing how how progress reached before timeout
    def describe_progress
      str = "#{identifier}: #{@title.capitalize} collection "
      str << "in response to #{@m_id} " if @m_id
      str << "didn't complete within #{@timeout}s, "
      str << "reached #{@messages.size}/#{@num}"
      str
    end

    # Check if we receive a NotAck related to initiating request, identified by @m_id.
    def reject_not_ack message
      return unless @m_id
      if message.is_a?(MessageNotAck)
        if message.attribute('oMId') == @m_id
          m_id_short = RSMP::Message.shorten_m_id @m_id, 8
          cancel RSMP::MessageRejected.new("#{@title} #{m_id_short} was rejected with '#{message.attribute('rea')}'")
          @distributor.log "#{identifier}: cancelled due to a NotAck", level: :debug
          true
        end
      end
    end

    # Handle message. and return true when we're done collecting
    def receive message
      raise ArgumentError unless message
      unless ready? || collecting?
        raise RuntimeError.new("can't process message when status is :#{@status}, title: #{@title}, desc: #{describe}") 
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

    def describe
    end

    # Match message against our collection criteria
    def perform_match message
      return false if reject_not_ack(message)
      return false unless acceptable?(message)
      #@distributor.log "#{identifier}: Looking at #{message.type} #{message.m_id_short}", level: :collect
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

    # An error occured upstream.
    # Check if we should cancel.
    def receive_error error, options={}
      case error
      when RSMP::SchemaError
        receive_schema_error error, options
      when RSMP::DisconnectError
        receive_disconnect error, options
      end
    end

    # Cancel if we received e schema error for a message type we're collecting
    def receive_schema_error error, options
      return unless @options.dig(:cancel,:schema_error)
      message = options[:message]
      return unless message
      klass = message.class.name.split('::').last
      return unless @filter&.type == nil || [@filter&.type].flatten.include?(klass)
      @distributor.log "#{identifier}: cancelled due to schema error in #{klass} #{message.m_id_short}", level: :debug
      cancel error
    end

    # Cancel if we received e notificaiton about a disconnect
    def receive_disconnect error, options
      return unless @options.dig(:cancel,:disconnect)
      @distributor.log "#{identifier}: cancelled due to a connection error: #{error.to_s}", level: :debug
      cancel error
    end

    # Abort collection
    def cancel error=nil
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
    def acceptable? message
      @filter == nil || @filter.accept?(message)
    end

    # return a string describing the types of messages we're collecting
    def describe_types
      [@filter&.type].flatten.join('/')
    end

    # return a string that describes whe number of messages, and type of message we're collecting
    def describe_num_and_type
      if @num && @num > 1
        "#{@num} #{describe_types}s"
      else
        describe_types
      end
    end

    # return a string that describes the attributes that we're looking for
    def describe_matcher
      h = {component: @filter&.component}.compact
      if h.empty?
        describe_num_and_type
      else
        "#{describe_num_and_type} #{h}"
      end
    end

    # return a string that describe how many many messages have been collected
    def describe_progress
      if @num
        "#{@messages.size} of #{@num} message#{'s' if @messages.size!=1} collected"
      else
        "#{@messages.size} message#{'s' if @messages.size!=1} collected"
      end        
    end

    # log when we start collecting
    def log_start
      @distributor.log "#{identifier}: Waiting for #{describe_matcher}".strip, level: :collect
    end

    # log current progress
    def log_incomplete
      @distributor.log "#{identifier}: #{describe_progress}", level: :collect
    end

    # log when we end collecting
    def log_complete
      @distributor.log "#{identifier}: Done", level: :collect
    end

    # get a short id in hex format, identifying ourself
    def identifier
      "Collect #{self.object_id.to_s(16)}"
    end

  end
end