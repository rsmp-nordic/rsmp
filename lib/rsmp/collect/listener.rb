# Receives items from a Notifier, as long as it's
# installed as a listener.

module RSMP
  class Listener
    include Inspect

    def initialize notifier, options={}
      @notifier = notifier
    end

    def change_notifier notifier
      @notifier.remove_listener self if @notifier
      @notifier = notifier
    end

    def notify message
    end

    def notify_error error, options={}
    end

    def listen &block
      @notifier.add_listener self
      yield
    ensure
      @notifier.remove_listener self
    end

  end
end