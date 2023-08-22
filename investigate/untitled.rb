class Supervisor < Worker
  attr_reader :workers

  def initialize(supervisor:, id:, level:, blueprint: {})
    super
    @workers = {}
    @messages = Async::Queue.new
    setup
  end

  def setup(ids = @blueprint.keys)
    workers = []
    ids.each do |id|
      workers << create_worker(id) unless @workers[id]
    end
    @workers << workers
    workers
  end

  def create_worker(id)
    return if @workers[id].nil?
    return unless (settings = @blueprint[id])

    @workers[id] = settings[:class].new(
      blueprint: settings[:workers],
      supervisor: self,
      id:,
      level: @level + 1
    )
  end

  def do_task
    run_workers
    fetch_post
  end

  def fetch_post
    Async do
      loop { receive @messages.dequeue }
    end
  end

  def receive(message)
    case message[:type]
    when :worker_failed
      worker_failed message[:from], message[:error]
    else
      log "unhandled #{message[:type].inspect}"
    end
  end

  def run_workers(workers = @workers.values)
    workers.each(&:run)
  end

  def stop_workers(workers = @workers.values.reverse)
    workers.each(&:stop)
  end

  def delete_workers(workers = @workers.values.reverse)
    workers.each(&:stop)
    @workers -= workers
  end

  def stop
    log 'stop'
    stop_workers
    stop_task
  end

  def failed(error)
    delete_workers
    super
  end

  def post(message)
    @messages.enqueue(message)
  end

  def worker_failed(worker, _error)
    id = worker.id
    settings = @blueprint[id]
    case settings[:strategy]
    when :one_for_one
      restart_one_for_one worker
    when :all_for_one
      restart_all_for_one
    when :rest_for_one
      restart_rest_for_one
    end
  end

  def restart_one_for_one(worker)
    id = worker.id
    @workers.delete id
    worker = create_worker(id)
    worker.run
  end

  def restart_all_for_one(worker)
    id = worker.id
    @workers.delete id
    delete_workers
    workers = setup
    run_workers workers
  end

  def restart_rest_for_one(worker)
    ids = @blueprint.keys.drop_while { |i| i != worker.id }
    rest = @workers.select { |id, _worker| ids.include?(id) }.values.reverse
    delete_workers rest
    workers = setup ids
    run_workers workers
  end

  def hierarchy
    super + @workers.map { |worker| worker[1].hierarchy }.join
  end

  def dig *args
    worker = @workers[args.shift]
    return worker if args.empty?
    return nil unless worker

    worker.dig(*args)
  end
end
