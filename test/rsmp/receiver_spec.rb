require_relative '../support/site_proxy_stub'

# Define test class at file level (replaces stub_const)
class TestReceiver
  include RSMP::Receiver

  def initialize(distributor, filter: nil)
    initialize_receiver distributor, filter: filter
  end

  def handle_message(message); end
end

describe RSMP::Receiver do
  with '#accept_message?' do
    it 'accepts message without filter' do
      receiver = TestReceiver.new nil
      message = RSMP::Watchdog.new
      expect(receiver.accept_message?(message)).to be == true
    end

    it 'accepts message filtered by type' do
      filter = RSMP::Filter.new(type: 'StatusUpdate')
      receiver = TestReceiver.new nil, filter: filter
      expect(receiver.accept_message?(RSMP::StatusUpdate.new)).to be == true
      expect(receiver.accept_message?(RSMP::Watchdog.new)).to be == false
    end

    it 'accepts message filtered by types array' do
      filter = RSMP::Filter.new(type: %w[StatusUpdate StatusRequest])
      receiver = TestReceiver.new nil, filter: filter
      expect(receiver.accept_message?(RSMP::StatusUpdate.new)).to be == true
      expect(receiver.accept_message?(RSMP::StatusRequest.new)).to be == true
      expect(receiver.accept_message?(RSMP::Watchdog.new)).to be == false
    end
  end

  with '#distribute' do
    it 'passes unfiltered message to #handle_message' do
      proxy = RSMP::SiteProxyStub.new nil
      receiver = TestReceiver.new proxy
      expect(receiver).to receive(:handle_message)
      proxy.add_receiver(receiver)

      message = RSMP::Watchdog.new
      proxy.distribute message
    end

    it 'passes filtered message to #handle_message' do
      proxy = RSMP::SiteProxyStub.new nil
      filter = RSMP::Filter.new(type: 'StatusUpdate')
      receiver = TestReceiver.new proxy, filter: filter
      proxy.add_receiver(receiver)

      received_messages = []
      mock(receiver).replace(:handle_message) { |msg| received_messages << msg }

      proxy.distribute RSMP::Watchdog.new
      expect(received_messages).to be == []

      message = RSMP::StatusUpdate.new
      proxy.distribute message
      expect(received_messages).to be == [message]
    end
  end
end
