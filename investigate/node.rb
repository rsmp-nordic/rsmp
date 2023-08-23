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
  attr_reader :id, :strategy, :level

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
    "<#{@id}>"
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
    raise 'Worker already exists' if @worker

    @worker = @worker_class.new self
  end

  # Runs our  worker inside an async task.
  # Uncaught errors are reported to supervisor,
  # which can then restart our (and possible others) worker,
  # depending on our restart strategy.
  def run
    @task = Async do |task|
      task.annotate(@id)
      create_worker
      @worker.run
    rescue StandardError => e
      @worker.fail e
      report_error e
    end
  end

  # Stop, by stopping our worker
  def stop
    stop_worker
  end

  # Stop our worker and the async task it's running in.
  def stop_worker
    @worker&.stop
    @task&.stop
    @worker = nil
    @task = nil
  end

  # Report an error to our supervisor.
  def report_error(error)
    message = { type: :node_failed, from: self, error: }
    @supervisor.post message
  end
end
