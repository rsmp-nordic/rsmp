# Receives items from a Notifier, as long as it's
# installed as a listener.

module RSMP
  class Listener
    include Inspect

    def initialize proxy, options={}
      @proxy = proxy
    end

    def notify message
    end

    def notify_error error
    end

    def listen &block
      @proxy.add_listener self
      yield
    ensure
      @proxy.remove_listener self
    end

  end
end