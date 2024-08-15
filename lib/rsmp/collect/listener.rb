# Receives items from a Notifier, as long as it's
# installed as a listener.
# Optionally can filter mesage using a Filter.

module RSMP
  class Listener
    include Inspect

    def initialize notifier, filter: nil
      @notifier = notifier
      @filter = filter
    end

    def change_notifier notifier
      @notifier.remove_listener self if @notifier
      @notifier = notifier
    end

    def notify message
      incoming(message) if accept_message?(message) 
    end

    def accept_message? message
      @filter == nil || @filter.accept?(message)
    end

    def notify_error error, options={}
    end

    private

    def incoming message
    end

  end
end