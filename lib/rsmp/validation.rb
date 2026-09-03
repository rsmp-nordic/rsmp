module RSMP
  # The result of validating a message against one or more schemas.
  Validation = Data.define(:violations) do
    def initialize(violations: [])
      raise ArgumentError, 'violations must be an Array' unless violations.is_a?(Array)

      super(violations: violations.map { |violation| Array(violation).dup.freeze }.freeze)
    end

    def valid?
      violations.empty?
    end

    def invalid?
      !valid?
    end

    def message
      violations.map { |item| item.reject { |part| part == '' } }.compact.join(', ').strip
    end
  end
end
