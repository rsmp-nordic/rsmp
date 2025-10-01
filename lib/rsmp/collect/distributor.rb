# Distributes messages to receivers

module RSMP
  module Distributor
    attr_reader :receivers

    include Inspect

    def inspect
      "#<#{self.class.name}:#{object_id}, #{inspector(:@receivers)}>"
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
      @receivers.each { |receiver| receiver.receive message }
    end

    def distribute_error(error, options = {})
      warn "[DEBUG] distribute_error #{error.class}: #{error.message}" if ENV['RSMP_DEBUG_STATES']
      @receivers.each { |receiver| receiver.receive_error error, options }
    end
  end
end
