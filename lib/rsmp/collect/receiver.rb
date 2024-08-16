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

    def receive message
      handle_message(message) unless reject_message?(message) 
    end

    def receive_error error, options={}
    end

    def accept_message? message
      !reject_message?(message)
    end

    def reject_message? message
      @filter&.reject?(message)
    end

    def handle_message message
    end


  
  end
end