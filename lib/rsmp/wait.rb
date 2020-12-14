# Helper for waiting for an Async condition using a block

module RSMP
  class Wait

    def self.wait_for task, condition, timeout, &block
      raise RuntimeError.new("Can't wait for state because task is stopped") unless task.running? 
      task.with_timeout(timeout) do
        while task.running? do
          value = condition.wait
          result = yield value 
          return result if result   # return result of check, if not nil
        end
      end
    end   

  end
end