module RSMP
  # Class which distributes messages to receivers
  module Distributor
    attr_reader :receivers

    def inspect
      "#<#{self.class.name}:#{object_id}}>"
    end

    def initialize_distributor
      @receivers = []
      @defer_distribution = false
      @deferred_messages = []
    end

    def clear_deferred_distribution
      @deferred_messages = []
    end

    def with_deferred_distribution
      was = @defer_distribution
      @defer_distribution = true
      yield
      distribute_queued
    ensure
      @defer_distribution = was
      @deferred_messages = []
    end

    def distribute_queued
      @deferred_messages.each { |message| distribute_immediately message }
    ensure
      @deferred_messages = []
    end

    def add_receiver(receiver)
      raise ArgumentError unless receiver

      @receivers << receiver unless @receivers.include? receiver
    end

    def remove_receiver(receiver)
      raise ArgumentError unless receiver

      @receivers.delete receiver
    end

    def distribute(message)
      raise ArgumentError unless message

      if @defer_distribution
        @deferred_messages << message
      else
        distribute_immediately message
      end
    end

    def distribute_immediately(message)
      @receivers.dup.each { |receiver| deliver(receiver, :receive, message) }
    end

    def distribute_event(event)
      raise ArgumentError, 'event must be an RSMP::Event' unless event.is_a?(RSMP::Event)

      @receivers.dup.each { |receiver| deliver(receiver, :receive_event, event) }
    end

    private

    def deliver(receiver, method, value)
      receiver.public_send(method, value)
    rescue StandardError => e
      remove_receiver(receiver)
      raise unless receiver.respond_to?(:crash)

      receiver.crash(e)
    end
  end
end
