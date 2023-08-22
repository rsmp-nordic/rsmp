# frozen_string_literal: true

require 'async'
require 'async/queue'

# A worker in a supervisor tree.
class Worker
  attr_reader :id

  # Create a worker
  def initialize(level:, blueprint: {}, supervisor: nil, id: nil)
    @id = id
    @supervisor = supervisor
    @blueprint = blueprint
    @level = level
    @task = nil
  end

  # Intend a string according to the tree level.
  def indent(str)
    '. ' * @level + str
  end

  # Output a string indented and with our id in front.
  def log(str)
    id_str = indent(@id.to_s)
    puts "#{id_str.ljust(20)} #{str}"
  end

  # Return our id indented.
  def hierarchy
    "#{indent(@id.to_s)}\n"
  end

  # Perform actual work inside an async work task.
  # Any ancaught errors will be reported to our supervisor.
  def run
    log 'run'
    @task = Async do |task|
      task.annotate(@id)
      do_task
    rescue StandardError => e
      log 'fail'
      failed e
    end
  end

  # Stop.
  # Will stop our work task.
  def stop
    log 'stop'
    stop_task
  end

  # Perform actual work.
  # This will be running inside our async work task.
  def do_task
    log 'done'
  end

  # Stop our work task if it's running.
  def stop_task
    return unless @task

    @task.stop
    @task = nil
  end

  # This is called if the actual work results in an uncaught error.
  # Reports the error to the supervisor.
  def failed(error)
    report_error(error)
  end

  # Report an error to our supervisor.
  def report_error(error)
    message = { type: :worker_failed, from: self, error: }
    @supervisor.post message
  end
end
