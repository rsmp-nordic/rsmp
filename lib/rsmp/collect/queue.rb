# Top-level RSMP namespace.
module RSMP
  # Receives items from a Distributor and keeps them in a queue.
  # The client can wait for messages and will get them one by one.
  class Queue
    include Receiver

    FAILURE_OPTIONS = {
      invalid_message: :invalid_message,
      connection_ended: :disconnect,
      missing_acknowledgement: :missing_acknowledgement
    }.freeze

    attr_reader :messages

    # Allow queues to be started by a proxy's collect factory, like collectors.
    alias start start_receiving
    alias stop stop_receiving

    def initialize(distributor, filter: nil, cancel: {})
      initialize_receiver distributor, filter: filter
      @cancel = cancel
      @condition = Async::Notification.new
      clear
    end

    def clear
      @messages = []
      @failure = nil
    end

    # Consume in order, discarding non-matches and retaining messages after the match.
    def wait_for_message(filter: nil, original: nil, timeout: nil)
      if timeout
        Async::Task.current.with_timeout(timeout) { next_message(filter, original) }
      else
        next_message(filter, original)
      end
    rescue Async::TimeoutError => e
      Result.failure(
        :timeout,
        message: "No #{wait_description(filter || @filter, original)} was received within #{timeout}s",
        source: :timeout,
        cause: e
      )
    end

    def wait_for_message!(...)
      wait_for_message(...).value!
    end

    def wait_for_status_update(code, direction: :in, component: nil, timeout: nil)
      filter = StatusFilter.new(type: 'StatusUpdate', component: component, any: [StatusMatcher.new('sCI' => code)],
                                **direction_options(direction))
      wait_for_message(filter: filter, timeout: timeout)
    end

    def wait_for_subscribe(code, direction: :in, component: nil, timeout: nil)
      filter = SubscriptionFilter.new(type: 'StatusSubscribe', component: component,
                                      any: [SubscriptionMatcher.new('sCI' => code)], **direction_options(direction))
      wait_for_message(filter: filter, timeout: timeout)
    end

    def wait_for_unsubscribe(code, direction: :in, component: nil, timeout: nil)
      filter = SubscriptionFilter.new(type: 'StatusUnsubscribe', component: component,
                                      any: [SubscriptionMatcher.new('sCI' => code)], **direction_options(direction))
      wait_for_message(filter: filter, timeout: timeout)
    end

    def wait_for_command_request(code, direction: :in, component: nil, timeout: nil)
      filter = CommandFilter.new(type: 'CommandRequest', component: component, any: [CommandMatcher.new('cCI' => code)],
                                 **direction_options(direction))
      wait_for_message(filter: filter, timeout: timeout)
    end

    def wait_for_command_response(code, direction: :in, component: nil, timeout: nil)
      filter = CommandFilter.new(type: 'CommandResponse', component: component,
                                 any: [CommandMatcher.new('cCI' => code)], **direction_options(direction))
      wait_for_message(filter: filter, timeout: timeout)
    end

    def wait_for_ack(original, direction: :in, timeout: nil)
      wait_for_message(filter: Filter.new(type: 'MessageAck', **direction_options(direction)), original: original,
                       timeout: timeout)
    end

    def handle_message(message)
      return if @failure

      @messages << message
      @condition.signal
    end

    # Failure handling is opt-in, preserving ordinary message-only queues.
    def receive_event(event)
      option = FAILURE_OPTIONS[event.type]
      return unless option && @cancel[option] && event.failure
      return if event.type != :connection_ended && event.message && reject_message?(event.message)

      @failure ||= event.failure
      @condition.signal
    end

    private

    def next_message(filter, original)
      loop do
        return Result.failure(failure: @failure) if @failure

        if @messages.empty?
          @condition.wait
        else
          result = match_message(@messages.shift, filter, original)
          return result if result
        end
      end
    end

    def match_message(message, filter, original)
      return if filter&.reject?(message)
      return if original && message.attributes['oMId'] != original.m_id

      if message.is_a?(MessageNotAck)
        return rejection_result(message, original) if original
        # Filter admits rejections even when their type was not requested.
        return unless explicit_not_ack?(filter)
      end

      Result.success(message)
    end

    def explicit_not_ack?(filter)
      types = filter&.type || @filter&.type
      types.nil? || types.include?('MessageNotAck')
    end

    def rejection_result(message, original)
      Result.failure(:message_rejected, message: "#{original.type} rejected: #{message.attributes['rea']}",
                                        source: :peer, context: { message: message })
    end

    def direction_options(direction)
      raise ArgumentError, 'direction must be :in or :out' unless %i[in out].include?(direction)

      { ingoing: direction == :in, outgoing: direction == :out }
    end

    def wait_description(filter, original)
      description = filter ? filter.describe : 'message'
      description += " for #{original.m_id}" if original
      description
    end
  end
end
