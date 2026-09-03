module RSMP
  # Reactor-confined, ordered delivery of background lifecycle events.
  module EventSource
    attr_reader :event_receivers

    def initialize_event_source
      @event_receivers = []
    end

    def add_event_receiver(receiver)
      raise ArgumentError, 'event receiver must respond to receive_event' unless receiver.respond_to?(:receive_event)

      @event_receivers << receiver unless @event_receivers.include?(receiver)
      receiver
    end

    def remove_event_receiver(receiver)
      @event_receivers.delete(receiver)
      receiver
    end

    def publish_event(event)
      raise ArgumentError, 'event must be an RSMP::Event' unless event.is_a?(Event)

      @event_receivers.dup.each do |receiver|
        receiver.receive_event(event)
      rescue StandardError => e
        remove_event_receiver(receiver)
        raise unless receiver.respond_to?(:crash)

        receiver.crash(e)
      end
      event
    end
  end
end
