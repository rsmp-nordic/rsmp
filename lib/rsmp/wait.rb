module RSMP
  module Wait
    # wait for an async condition to signal, then yield to block
    # if block returns true we're done. otherwise, wait again
    def wait_for condition, timeout, &block
      raise RuntimeError.new("Can't wait for condition because task is not running") unless @task.running?
      @task.with_timeout(timeout) do
        while @task.running? do
          value = condition.wait
          result = yield value 
          return result if result   # return result of check, if not nil
        end
      end
    end   
  end
end