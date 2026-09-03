module RSMP
  # The disposition of a successfully submitted outbound message.
  Delivery = Data.define(:message, :state) do
    def initialize(message:, state:)
      raise ArgumentError, 'delivery state must be :sent or :buffered' unless %i[sent buffered].include?(state)

      super
    end

    def sent?
      state == :sent
    end

    def buffered?
      state == :buffered
    end
  end
end
