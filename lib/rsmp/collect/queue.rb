# Receives items from a Distributor and keeps them in a queue.
# The client can wait for mesages and will get them one by one.

module RSMP
  class Queue
    include Receiver

    attr_reader :messages

    def initialize distributor, filter: nil, task:
      initialize_receiver distributor, filter: filter
      @condition = Async::Notification.new
      @task = task
      clear
    end

    def clear
      @messages = []
    end

    def wait_for_message timeout: nil
      if @messages.empty?
        if timeout
          @task.with_timeout(timeout) { @condition.wait }
        else
          @condition.wait
        end
      end
      @messages.shift
    rescue Async::TimeoutError
      raise RSMP::TimeoutError
    end

    def handle_message message
      @messages << message
      @condition.signal
    end
  end
end