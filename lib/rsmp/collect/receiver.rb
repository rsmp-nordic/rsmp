module RSMP
  # Receives items from a Distributor when included as a receiver.
  # Optionally filter messages using a Filter.
  module Receiver
    include Inspect

    def initialize_receiver(distributor, filter: nil)
      @distributor = distributor
      @filter = filter
    end

    def start_receiving
      @distributor.add_receiver(self)
    end

    def stop_receiving
      @distributor.remove_receiver(self)
    end

    def receive(message)
      handle_message(message) if accept_message?(message)
    end

    def receive_error(error, options = {}); end

    def accept_message?(message)
      @filter.nil? || @filter.accept?(message)
    end

    def reject_message?(message)
      !accept_message?(message)
    end

    def handle_message(message); end
  end
end
