# Receives items from a Distributor, as long as it's
# installed as a receiver.
# Optionally can filter mesage using a Filter.

module RSMP
  module Receiver
    include Inspect

    def initialize_receiver distributor, filter: nil
      @distributor = distributor
      @filter = filter
    end

    def start_receiving
      @distributor.add_receiver(self)
    end

    def stop_receiving
      @distributor.remove_receiver(self)
    end

    def receive message
      handle_message(message) if accept_message?(message) 
    end

    def receive_error error, options={}
    end

    def accept_message? message
      @filter == nil || @filter.accept?(message)
    end

    def reject_message? message
      !accept_message?(message)
    end

    def handle_message message
    end
  end
end