module RSMP
  # Result values represent the expected outcome of finite operations.
  module Result
    # A successfully completed operation.
    Success = Data.define(:value) do
      def success?
        true
      end

      def failure?
        false
      end

      def failure
        nil
      end

      def value!
        value
      end

      def map
        Result.success(yield(value))
      end

      def and_then
        yield(value)
      end
    end

    # An expected operational failure.
    Failure = Data.define(:failure) do
      def initialize(failure:)
        raise ArgumentError, 'failure must be an RSMP::Failure' unless failure.is_a?(RSMP::Failure)

        super
      end

      def success?
        false
      end

      def failure?
        true
      end

      def value
        nil
      end

      def value!
        exception = OperationError.new(failure)
        raise exception, cause: failure.cause if failure.cause

        raise exception
      end

      def map
        self
      end

      def and_then
        self
      end
    end

    module_function

    def success(value = nil)
      Success.new(value)
    end

    def failure(code = nil, failure: nil, **details)
      Failure.new(
        failure: failure || RSMP::Failure.new(
          code: code,
          message: details.fetch(:message, code),
          source: details.fetch(:source, :operation),
          context: details.fetch(:context, {}),
          cause: details[:cause]
        )
      )
    end
  end

  # Raised by bang APIs when an expected failure result is explicitly unwrapped.
  class OperationError < Error
    attr_reader :failure

    def initialize(failure)
      @failure = failure
      super(failure.message)
    end
  end
end
