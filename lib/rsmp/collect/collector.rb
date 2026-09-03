module RSMP
  # Collects matching messages and resolves once with an immutable Result.
  class Collector
    include Receiver
    include Reporting
    include Logging

    attr_reader :messages, :m_id, :initiator

    def initialize(distributor, options = {})
      initialize_receiver distributor, filter: options[:filter]
      @options = {
        cancel: {
          invalid_message: true,
          disconnect: true
        }
      }.deep_merge(options)
      @timeout = options[:timeout]
      @num = options[:num]
      @initiator = options[:initiator]
      @m_id = options[:m_id] || @initiator&.attributes&.dig('mId')
      make_title(options[:title])
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

    def reset
      @messages = []
      @completion = Completion.new
      @active = false
    end

    def active?
      @active
    end

    alias collecting? active?

    def inspect
      "#<#{self.class.name}:#{object_id}, message:#{@messages}>"
    end

    def collect(&)
      start(&)
      wait
    ensure
      stop
    end

    def collect!(&)
      collect(&).value!.messages
    end

    # The configured timeout terminates this collection. Completion retains the
    # result, so every current or future waiter observes the same value.
    def wait
      raise 'collector has not been started' unless active? || @completion.resolved?

      observed = @completion.wait(timeout: @timeout)
      if timeout_result?(observed)
        finish_failure(observed.failure.with(message: describe_progress))
        observed = @completion.wait
      end
      observed
    end

    def wait!
      wait.value!.messages
    end

    def start(&block)
      raise 'collector is already active' if active?

      @block = block
      raise ArgumentError, 'num, timeout or block must be provided' unless @num || @timeout || @block

      reset
      @active = true
      log_start
      @distributor.add_receiver(self)
      self
    end

    def stop
      return self unless @active

      @active = false
      @distributor.remove_receiver(self)
      self
    end

    # Check for a NotAck related to the initiating request.
    def reject_not_ack?(message)
      return false unless @m_id
      return false unless message.is_a?(MessageNotAck)
      return false unless message.attribute('oMId') == @m_id

      m_id_short = RSMP::Message.shorten_m_id(@m_id, 8)
      finish_failure(
        Failure.new(
          code: :message_rejected,
          message: "#{@title} #{m_id_short} was rejected with '#{message.attribute('rea')}'",
          source: :peer,
          context: { message: message, original_message_id: @m_id }
        )
      )
      @distributor.log "#{identifier}: rejected by a NotAck", level: :debug
      true
    end

    def receive(message)
      return unless active?

      if perform_match?(message)
        done? ? complete : incomplete
      end
      active?
    end

    def describe; end

    def perform_match?(message)
      return false if reject_not_ack?(message)
      return false unless acceptable?(message)

      if @block
        status = Array(@block.call(message))
        return false unless active?

        keep(message) if status.include?(:keep)
      else
        keep(message)
      end
      true
    end

    def done?
      @num && @messages.size >= @num
    end

    def complete
      finish_success(build_collection)
      log_complete
    end

    def incomplete
      log_incomplete
    end

    def receive_event(event)
      return unless active?

      case event.type
      when :invalid_message
        receive_invalid_message(event)
      when :connection_ended
        receive_connection_ended(event)
      end
    end

    def receive_invalid_message(event)
      return unless @options.dig(:cancel, :invalid_message)
      return unless event.message
      return unless acceptable?(event.message)

      finish_failure(event.failure)
    end

    def receive_connection_ended(event)
      return unless @options.dig(:cancel, :disconnect)

      finish_failure(event.failure)
    end

    # Explicit cancellation is an expected caller-controlled result.
    def cancel(reason = 'Collection cancelled')
      finish_failure(
        Failure.new(code: :cancelled, message: reason.to_s, source: :local)
      )
    end

    def fail(failure)
      raise ArgumentError, 'failure must be an RSMP::Failure' unless failure.is_a?(Failure)

      finish_failure(failure)
    end

    # Unexpected receiver/callback failures reject the completion so waiters see
    # the original exception and stack trace.
    def crash(error)
      return unless active?

      @completion.crash(error)
      stop
    end

    def keep(message)
      @messages << message
    end

    def acceptable?(message)
      @filter.nil? || @filter.accept?(message)
    end

    def build_collection
      Collection.new(messages: @messages)
    end

    private

    def timeout_result?(result)
      result.failure? && result.failure.code == :timeout && !@completion.resolved?
    end

    def finish_success(collection)
      @completion.succeed(collection)
      stop
    end

    def finish_failure(failure)
      @completion.fail(failure)
      stop
    end
  end
end
