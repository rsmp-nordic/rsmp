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
      Async do |task|
        task.annotate "#{self.class.name} main task"
        @task = task
        run
        stop_subtasks
        @task = nil
      end
      self
    end

    # initiate restart by raising a Restart exception
    def restart
      raise Restart.new "restart initiated by #{self.class.name}:#{object_id}"
    end

    # get the status of our task, or nil of no task
    def status
      @task.status if @task
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
      @task.wait if @task
    end

    # stop our task
    def stop
      stop_subtasks
      terminate if @task
    end

    def stop_subtasks
    end

    def self.print_hierarchy task=Async::Task.current.reactor, level=0
      if task.parent
        status = task.status
        puts "#{'. '*level}#{task.object_id} #{task.annotation.to_s}: #{status}"
      else
        puts "#{'. '*level}#{task.object_id} reactor"
      end
      task.children&.each do |child|
        print_hierarchy child, level+1
      end
    end


    # stop our task and any subtask
    def terminate
      @task.stop
      @task = nil
    end

  end
end