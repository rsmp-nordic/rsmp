# Distributes messages to listeners

module RSMP
  module Notifier
    attr_reader :listeners

    include Inspect

    def inspect
      "#<#{self.class.name}:#{self.object_id}, #{inspector(:@listeners)}>"
    end

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

    def notify message
      @listeners.each { |listener| listener.notify message }
    end

    def distribute_error error
      @listeners.each { |listener| listener.notify_error error }
    end
  end
end
