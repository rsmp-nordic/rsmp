module RSMP
  # Explicit ownership for a long-running Async task tree.
  module Task
    class ConditionWaitTimeout < Async::TimeoutError; end

    attr_reader :task

    def initialize_task
      @task = nil
      @termination_completion = Completion.new
    end

    # Start under an explicit Async parent. A current task is accepted for
    # convenience, but this library never creates a hidden root reactor.
    def start(parent: Async::Task.current)
      return @task if @task&.running?

      valid_parent = parent.respond_to?(:async) && (!parent.respond_to?(:running?) || parent.running?)
      raise ArgumentError, 'an active Async parent task is required' unless valid_parent

      child = parent.async do |task|
        task.annotate "#{self.class.name} main task"
        @task = task
        run
      ensure
        stop_subtasks
      end
      @task = child
    end

    def restart
      termination_completion.succeed(Termination.new(reason: :restart, source: self))
    end

    def wait_for_termination
      termination_completion.wait
    end

    def task_status
      @task&.status
    end

    def run
      start_subtasks
    end

    # Async::Task#wait raises unexpected child failures and returns nil for
    # cancellation, matching Async's native task contract.
    def wait
      @task&.wait
    end

    def stop
      stop_task
    end

    def stop_subtasks; end

    def stop_task
      task = @task
      return unless task&.running?

      task.cancel
      task.wait unless task.current?
    end

    # Wait for an edge-triggered condition and return an expected timeout as a
    # Result. Async cancellation is not rescued and therefore propagates.
    def wait_for_condition(condition, timeout:, task: Async::Task.current, &block)
      raise ArgumentError, 'an active Async task is required' unless task&.running?

      value = task.with_timeout(timeout, ConditionWaitTimeout) do
        loop do
          signalled = condition.wait
          break signalled unless block

          matched = yield(signalled)
          break matched if matched
        end
      end
      Result.success(value)
    rescue ConditionWaitTimeout => e
      Result.failure(
        :timeout,
        message: "Condition was not met within #{timeout}s",
        source: :timeout,
        cause: e
      )
    end

    def wait_for_condition!(...)
      wait_for_condition(...).value!
    end

    private

    def termination_completion
      @termination_completion ||= Completion.new
    end
  end
end
