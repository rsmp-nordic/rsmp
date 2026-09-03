module RSMP
  # A resolve-once Async completion. Expected failures resolve to Result::Failure;
  # unexpected exceptions reject the promise and retain their original backtrace.
  class Completion
    def initialize
      @promise = Async::Promise.new
    end

    def resolved?
      @promise.resolved?
    end

    def succeed(value = nil)
      @promise.resolve(Result.success(value))
    end

    def fail(failure = nil, **)
      result = if failure.is_a?(RSMP::Failure)
                 Result.failure(failure: failure)
               else
                 Result.failure(failure, **)
               end
      @promise.resolve(result)
    end

    def crash(exception)
      @promise.reject(exception)
    end

    # A wait timeout bounds this caller's wait; it does not resolve or cancel the
    # underlying operation.
    def wait(timeout: nil)
      @promise.wait(timeout: timeout)
    rescue Async::TimeoutError => e
      return @promise.wait if @promise.resolved?

      Result.failure(
        :timeout,
        message: "Operation did not complete within #{timeout}s",
        source: :timeout,
        cause: e
      )
    end

    def wait!(timeout: nil)
      wait(timeout: timeout).value!
    end
  end
end
