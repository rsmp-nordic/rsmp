module RSMP
  # An expected operational failure. Failures are values: they describe why an
  # operation could not complete without changing Async task control flow.
  Failure = Data.define(:code, :message, :source, :context, :cause) do
    def initialize(code:, message:, source:, context: {}, cause: nil)
      raise ArgumentError, 'failure code must be a Symbol' unless code.is_a?(Symbol)
      raise ArgumentError, 'failure source must be a Symbol' unless source.is_a?(Symbol)
      raise ArgumentError, 'failure context must be a Hash' unless context.is_a?(Hash)

      super(
        code: code,
        message: message.to_s.freeze,
        source: source,
        context: context.dup.freeze,
        cause: cause
      )
    end

    def to_s
      message.empty? ? code.to_s : message
    end
  end
end
