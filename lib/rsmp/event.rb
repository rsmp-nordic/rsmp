module RSMP
  # A typed occurrence produced by a long-running node or connection.
  Event = Data.define(:type, :source, :session_id, :message, :failure, :context, :at) do
    def initialize(type:, source:, session_id: nil, message: nil, failure: nil, context: {}, at: Time.now)
      raise ArgumentError, 'event type must be a Symbol' unless type.is_a?(Symbol)
      raise ArgumentError, 'event context must be a Hash' unless context.is_a?(Hash)

      super(
        type: type,
        source: source,
        session_id: session_id,
        message: message,
        failure: failure,
        context: context.dup.freeze,
        at: at
      )
    end
  end
end
