# Distributes messages to listeners

module RSMP
  module Notifier

    def initialize_distributor
      @listeners = []
    end

    def add_listener listener
      raise ArgumentError unless listener
      @listeners << listener unless @listeners.include? listener
    end

    def remove_listener listener
      raise ArgumentError unless listener
      @listeners.delete listener
    end

    def notify item
      @listeners.each { |listener| listener.notify item }
    end
  end
end
