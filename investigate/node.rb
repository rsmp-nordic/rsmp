# frozen_string_literal: true

require 'async'
require 'async/queue'
require_relative 'worker'

# A node in a supervisor tree.
# Uses a Worker do do actual work.
# If the worker fails, we report it to out supervisor which will
# then take care or restarting our worker, and other workers
# as well, depending on our restart strategy
class Node
  attr_reader :id, :strategy, :level, :worker

  # Create a node
  def initialize(id:, worker_class:, strategy:, supervisor:, blueprint: nil)
    _blueprint = blueprint # avoid Rubocop warning about unused arg
    @id = id
    @supervisor = supervisor
    @strategy = strategy
    @worker_class = worker_class
    @task = nil
    @level = nil
    adjust_level
    @supervisor&.add_node(self)
  end

  # Reset our level to supervisor level + 1
  def adjust_level
    @level = @supervisor ? @supervisor.level + 1 : 0
  end

  # More readable debug output
  def inspect
    "Node <#{@id}>"
  end

  # Intend a string according to the tree level.
  def indent(str)
    '. ' * @level + str
  end

  # Output a string indented and with our id in front.
  def log(str)
    id_str = indent(@id.to_s)
    puts "#{id_str.ljust(12)} #{str}"
  end

  # Return our id indented.
  def hierarchy
    {}
  end

  # Construct worker, using our worker class.
  def create_worker
    @worker = @worker_class.new(self) unless @worker
  end

  # Run our worker inside an async task.
  # Uncaught errors are reported to our supervisor,
  # which can then restart ours (and possible others) worker,
  # depending on our restart strategy.
  def run
    @task = Async do |task|
      task.annotate(@id)
      work
    rescue StandardError => e
      @worker.failed(e) if @worker
      report_error e
    end
  end

  def work
    create_worker
    @worker.run
  end

  # Stop, by stopping our worker
  def stop
    stop_worker
  end

  # Stop our worker and the async task it's running in.
  def stop_worker
    @worker&.stop
    @worker = nil
    @task&.stop
    @task = nil
  end

  # Report an error to our supervisor.
  def report_error(error)
    message = { type: :node_failed, from: self, error: }
    @supervisor.post message
  end
end
