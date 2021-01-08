# Receives messages from a Distributor, as long as it's
# installed as a receiver.

module RSMP
  class Receiver

    def initialize proxy
      @proxy = proxy
    end

    def receive item
    end

    def siphon &block
      @proxy.add_receiver self
      yield
    ensure
      @proxy.remove_receiver self
    end

  end
end