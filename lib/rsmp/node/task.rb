module RSMP
  class Restart < StandardError
  end

  module Task
    attr_reader :task

    def initialize_task
      @task = nil
    end

    # start our async tasks and return immediately
    # run() will be called inside the task to perform actual long-running work
    def start
      return if @task

      # Use current task context if available, otherwise create new reactor
      if Async::Task.current?
        Async::Task.current.async do |task|
          task.annotate "#{self.class.name} main task"
          @task = task
          run
          stop_subtasks
          @task = nil
        end
      else
        Async do |task|
          task.annotate "#{self.class.name} main task"
          @task = task
          run
          stop_subtasks
          @task = nil
        end
      end
      self
    end

    # initiate restart by raising a Restart exception
    def restart
      raise Restart, "restart initiated by #{self.class.name}:#{object_id}"
    end

    # get the status of our task, or nil of no task
    def task_status
      @task&.status
    end

    # perform any long-running work
    # the method will be called from an async task, and should not return
    # if subtasks are needed, the method should call wait() on each of them
    # once running, ready() must be called
    def run
      start_subtasks
    end

    # wait for our task to complete
    def wait
      @task&.wait
    end

    # stop our task
    def stop
      stop_subtasks
      stop_task if @task
    end

    def stop_subtasks; end

    # stop our task and any subtask
    def stop_task
      @task.stop
      @task = nil
    end

    # wait for an async condition to signal, then yield to block
    # if block returns true we're done. otherwise, wait again
    def wait_for_condition(condition, timeout:, task: Async::Task.current, &block)
      raise "Can't wait without a task" unless task

      task.with_timeout(timeout) do
        while task.running?
          value = condition.wait
          return value unless block

          result = yield value
          return result if result
        end
        raise "Can't wait for condition because task #{task.object_id} #{task.annotation} is not running"
      end
    rescue Async::TimeoutError
      raise RSMP::TimeoutError
    end
  end
end
