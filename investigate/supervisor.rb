# frozen_string_literal: true

require_relative 'worker'

# Supervises workers in a supervisor tree.
class Supervisor < Worker
  attr_reader :workers

  # Create supervisor
  def initialize(supervisor:, id:, level:, blueprint:)
    super
    @workers = {}
    @messages = Async::Queue.new
    setup
  end

  # Create workers specified in our blueprint,
  # but not actually existing yet.
  def setup(ids = @blueprint.keys)
    missing = ids - @workers.keys
    add = {}
    missing.each { |id| add[id] = create_worker(id) }
    @workers.merge add
    add.values
  end

  # Create a worker, specified by id.
  # The object class is read from our blueprint.
  def create_worker(id)
    return unless @workers[id].nil?

    settings = @blueprint[id]
    return unless settings

    @workers[id] = settings[:class].new(
      blueprint: settings[:workers],
      supervisor: self, id:, level: @level + 1
    )
  end

  # Perform actual work. For us this means
  # running all our workers, and then fetching  post.
  def do_task
    run_workers
    fetch_post
  end

  # Fetch post in an async task by waiting for messages
  # in our post queue.
  def fetch_post
    Async { loop { receive @messages.dequeue } }
  end

  # A messages was receive from our post queue
  # Call the appropriate method, depending on the message type.
  def receive(message)
    case message[:type]
    when :worker_failed
      worker_failed message[:from], message[:error]
    else
      log "unhandled #{message[:type].inspect}"
    end
  end

  # Run a list of workers. (Defauls to all workers.)
  def run_workers(workers = @workers.values)
    workers.each(&:run)
  end

  # Stop a list of workers. (Defauls to all workers.)
  def stop_workers(workers = @workers.values.reverse)
    workers.each(&:stop)
  end

  # Delete a list workers. (Defauls to all workers.)
  # Stops workers before they are deleted.
  def delete_workers(workers = @workers.values.reverse)
    workers.each(&:stop)
    @workers.delete workers
  end

  # Stop.
  # Will stop our workers, and then our work task.
  def stop
    log 'stop'
    stop_workers
    stop_task
  end

  # We failed.
  # Delete our workers, and then report the error to
  # our supervisor higher up the tree.
  def failed(error)
    delete_workers
    report_error(error)
  end

  # Place a message in our message queue.
  def post(message)
    @messages.enqueue(message)
  end

  # One of our workers failed.
  # Restart the worker, and possible other workers, depending
  # on the policy specified in our blueprint:
  #   one for one:  just the failed worker
  #   rest for one: the failed worker and workers specified after it in the blueprint
  #   all for one: all our workers
  #
  # Note that a worker can itself be a supervisor, in which case restarting
  # it will restart everything under it.
  def worker_failed(worker, _error)
    case @blueprint[worker.id][:strategy]
    when :one_for_one
      restart_one_for_one worker
    when :all_for_one
      restart_all_for_one worker
    when :rest_for_one
      restart_rest_for_one worker
    end
  end

  # Restart worker
  def restart_one_for_one(worker)
    @workers.delete(worker.id)
    create_worker(worker.id).run
  end

  # Restart worker, plus workers specified after it in the blueprint
  def restart_rest_for_one(worker)
    ids = @blueprint.keys.drop_while { |i| i != worker.id }
    rest = @workers.select { |id, _worker| ids.include?(id) }.values.reverse
    delete_workers rest
    workers = setup ids
    run_workers workers
  end

  # Restart all workers
  def restart_all_for_one(worker)
    @workers.delete(worker.id)
    delete_workers
    workers = setup
    run_workers workers
  end

  # Build string showing supervisor tree
  def hierarchy
    super + @workers.map { |worker| worker[1].hierarchy }.join
  end

  # Find a worker by traversing the tree according to
  # the list of ids.
  def dig *args
    worker = @workers[args.shift]
    return worker if args.empty?
    return nil unless worker

    worker.dig(*args)
  end
end
