module RSMP
  module Wait
    # wait for an async condition to signal, then yield to block
    # if block returns true we're done. otherwise, wait again
    def wait_for_condition condition, timeout:, task:Async::Task.current, &block
      unless task
        raise RuntimeError.new("Can't wait without a task")
      end
      task.with_timeout(timeout) do
        while task.running?
          value = condition.wait
          return value unless block
          result = yield value
          return result if result
        end
        raise RuntimeError.new("Can't wait for condition because task #{task.object_id} #{task.annotation} is not running")
      end
    rescue Async::TimeoutError
      raise RSMP::TimeoutError.new
    end
  end
end