RSpec.describe RSMP::Listener do

  describe '#accept_message?' do
    it 'accepts message without filter' do
      listener = RSMP::Listener.new nil
      message = RSMP::Watchdog.new
      expect(listener.accept_message?(message)).to be(true)    
    end

    it 'accepts message filtered by type' do
      filter =  RSMP::Filter.new(type: 'StatusUpdate')
      listener = RSMP::Listener.new nil, filter: filter
      expect(listener.accept_message?(RSMP::StatusUpdate.new)).to be(true)    
      expect(listener.accept_message?(RSMP::Watchdog.new)).to be(false)    
    end

    it 'accepts message filtered by types array' do
      filter =  RSMP::Filter.new(type: ['StatusUpdate','StatusRequest'])
      listener = RSMP::Listener.new nil, filter: filter
      expect(listener.accept_message?(RSMP::StatusUpdate.new)).to be(true)    
      expect(listener.accept_message?(RSMP::StatusRequest.new)).to be(true)    
      expect(listener.accept_message?(RSMP::Watchdog.new)).to be(false)    
    end
  end

  describe '#notify' do
    it 'passes unfiltered message to #incoming' do
      proxy = RSMP::SiteProxyStub.new nil
      listener = RSMP::Listener.new proxy
      allow(listener).to receive(:incoming)
      proxy.add_listener(listener)

      message = RSMP::Watchdog.new
      proxy.notify message
      expect(listener).to have_received(:incoming).with(message).once
    end

    it 'passes filtered message to #incoming' do
      proxy = RSMP::SiteProxyStub.new nil
      filter =  RSMP::Filter.new(type: 'StatusUpdate')
      listener = RSMP::Listener.new proxy, filter: filter
      proxy.add_listener(listener)
      allow(listener).to receive(:incoming)

      message = RSMP::Watchdog.new
      proxy.notify message
      expect(listener).to_not have_received(:incoming)

      message = RSMP::StatusUpdate.new
      proxy.notify message
      expect(listener).to have_received(:incoming).with(message).once
    end

  end
end
