module RSMP
  # An explicit reason for a long-running service task to finish normally.
  Termination = Data.define(:reason, :source) do
    def initialize(reason:, source:)
      raise ArgumentError, 'termination reason must be a Symbol' unless reason.is_a?(Symbol)

      super
    end
  end
end
