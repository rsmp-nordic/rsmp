# Receives messages from a Notifier, as long as it's
# installed as a listener.
# Can listen for ingoing and/or outgoing messages.

module RSMP
  class Listener

    def initialize proxy, options={}
      @proxy = proxy
      @ingoing = options[:ingoing] == nil ? true  : options[:ingoing]
      @outgoing = options[:outgoing] == nil ? false : options[:outgoing]
    end

    def ingoing?
      ingoing == true
    end

    def outgoing?
      outgoing == true
    end

    def notify item
    end

    def siphon &block
      @proxy.add_listener self
      yield
    ensure
      @proxy.remove_listener self
    end

  end
end