require 'rsmp'

describe RSMP::EventSource do
  let(:publisher_class) do
    Class.new do
      include RSMP::EventSource

      def initialize
        initialize_event_source
      end
    end
  end

  it 'delivers typed events synchronously in subscriber order' do
    publisher = publisher_class.new
    received = []
    first = Object.new
    second = Object.new
    first.define_singleton_method(:receive_event) { |event| received << [:first, event] }
    second.define_singleton_method(:receive_event) { |event| received << [:second, event] }
    publisher.add_event_receiver(first)
    publisher.add_event_receiver(second)
    event = RSMP::Event.new(type: :connection_ended, source: publisher)

    publisher.publish_event(event)

    expect(received).to be == [[:first, event], [:second, event]]
  end

  it 'removes a faulty subscriber and propagates the original exception' do
    publisher = publisher_class.new
    receiver = Object.new
    receiver.define_singleton_method(:receive_event) { |_event| raise 'subscriber bug' }
    publisher.add_event_receiver(receiver)
    event = RSMP::Event.new(type: :invalid_message, source: publisher)

    expect { publisher.publish_event(event) }.to raise_exception(RuntimeError, message: be == 'subscriber bug')
    expect(publisher.event_receivers).to be(:empty?)
  end
end
