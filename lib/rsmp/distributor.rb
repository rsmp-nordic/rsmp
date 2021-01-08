# Distributes messages to receivers

module RSMP
  module Distributor

    def initialize_distributor
      @receivers = []
    end

    def add_receiver receiver
      raise ArgumentError unless receiver
      @receivers << receiver
    end

    def remove_receiver receiver
      raise ArgumentError unless receiver
      @receivers.delete receiver
    end

    def distribute item
      @receivers.each { |receiver| receiver.receive item }
    end

    def clear
      @receivers.each { |receiver| receiver.clear }
    end
  end
end
