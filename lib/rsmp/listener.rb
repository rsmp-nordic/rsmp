# Receives items from a Notifier, as long as it's
# installed as a listener.

module RSMP
  class Listener

    def initialize proxy, options={}
      @proxy = proxy
    end

    def notify item
    end

    def listen &block
      @proxy.add_listener self
      yield
    ensure
      @proxy.remove_listener self
    end

  end
end