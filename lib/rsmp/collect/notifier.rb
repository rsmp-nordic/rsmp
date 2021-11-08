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
      @defer_notify = false
      @notify_queue = []
    end

    def clear_deferred_notify &block
      @notify_queue = []
    end

    def deferred_notify &block
      was, @defer_notify = @defer_notify, true
      yield
      dequeue_notify
    ensure
      @defer_notify = was
    end

    def dequeue_notify
      @notify_queue.each { |message| notify_without_defer message }
    ensure
      @notify_queue = []
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
      raise ArgumentError unless message
      if @defer_notify
        @notify_queue << message
      else
        notify_without_defer message
      end
    end

    def notify_without_defer message
      @listeners.each { |listener| listener.notify message }
    end

    def distribute_error error, options={}
      @listeners.each { |listener| listener.notify_error error, options }
    end
  end
end
