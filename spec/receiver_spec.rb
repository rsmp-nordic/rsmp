RSpec.describe RSMP::Receiver do
  class TestReceiver
    include RSMP::Receiver

    def initialize(distributor, filter: nil)
      initialize_receiver distributor, filter: filter
    end
  end

  describe '#accept_message?' do
    it 'accepts message without filter' do
      receiver = TestReceiver.new nil
      message = RSMP::Watchdog.new
      expect(receiver.accept_message?(message)).to be(true)
    end

    it 'accepts message filtered by type' do
      filter =  RSMP::Filter.new(type: 'StatusUpdate')
      receiver = TestReceiver.new nil, filter: filter
      expect(receiver.accept_message?(RSMP::StatusUpdate.new)).to be(true)
      expect(receiver.accept_message?(RSMP::Watchdog.new)).to be(false)
    end

    it 'accepts message filtered by types array' do
      filter =  RSMP::Filter.new(type: %w[StatusUpdate StatusRequest])
      receiver = TestReceiver.new nil, filter: filter
      expect(receiver.accept_message?(RSMP::StatusUpdate.new)).to be(true)
      expect(receiver.accept_message?(RSMP::StatusRequest.new)).to be(true)
      expect(receiver.accept_message?(RSMP::Watchdog.new)).to be(false)
    end
  end

  describe '#distribute' do
    it 'passes unfiltered message to #handle_message' do
      proxy = RSMP::SiteProxyStub.new nil
      receiver = TestReceiver.new proxy
      allow(receiver).to receive(:handle_message)
      proxy.add_receiver(receiver)

      message = RSMP::Watchdog.new
      proxy.distribute message
      expect(receiver).to have_received(:handle_message).with(message).once
    end

    it 'passes filtered message to #handle_message' do
      proxy = RSMP::SiteProxyStub.new nil
      filter = RSMP::Filter.new(type: 'StatusUpdate')
      receiver = TestReceiver.new proxy, filter: filter
      proxy.add_receiver(receiver)
      allow(receiver).to receive(:handle_message)

      message = RSMP::Watchdog.new
      proxy.distribute message
      expect(receiver).to_not have_received(:handle_message)

      message = RSMP::StatusUpdate.new
      proxy.distribute message
      expect(receiver).to have_received(:handle_message).with(message).once
    end
  end
end
