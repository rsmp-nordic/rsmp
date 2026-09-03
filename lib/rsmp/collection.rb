module RSMP
  # Immutable snapshot returned by a completed collector.
  Collection = Data.define(:messages, :reached, :matcher_status) do
    def initialize(messages:, reached: [], matcher_status: {})
      super(
        messages: messages.dup.freeze,
        reached: reached.dup.freeze,
        matcher_status: matcher_status.dup.freeze
      )
    end
  end
end
