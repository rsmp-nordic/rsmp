# Top-level RSMP namespace.
module RSMP
  # Receives items from a Distributor and keeps them in a queue.
  # The client can wait for messages and will get them one by one.
  class Queue
    include Receiver

    attr_reader :messages

    def initialize(distributor, filter: nil)
      initialize_receiver distributor, filter: filter
      @condition = Async::Notification.new
      clear
    end

    def clear
      @messages = []
    end

    def wait_for_message(timeout: nil)
      if @messages.empty?
        if timeout
          Async::Task.current.with_timeout(timeout) { @condition.wait }
        else
          @condition.wait
        end
      end
      Result.success(@messages.shift)
    rescue Async::TimeoutError => e
      Result.failure(
        :timeout,
        message: "No message was received within #{timeout}s",
        source: :timeout,
        cause: e
      )
    end

    def wait_for_message!(...)
      wait_for_message(...).value!
    end

    def handle_message(message)
      @messages << message
      @condition.signal
    end
  end
end
