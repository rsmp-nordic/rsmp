# frozen_string_literal: true

require 'async'
require 'async/queue'

# A worker in a supervisor tree
class Worker
  attr_reader :id

  def initialize(level:, blueprint: {}, supervisor: nil, id: nil)
    @id = id
    @supervisor = supervisor
    @blueprint = blueprint
    @level = level
    @task = nil
  end

  def indent(str)
    '. ' * @level + str
  end

  def log(str)
    id_str = indent(@id.to_s)
    puts "#{id_str.ljust(20)} #{str}"
  end

  def hierarchy
    "#{indent(@id.to_s)}\n"
  end

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

  def stop
    log 'stop'
    stop_task
  end

  def do_task
    log 'done'
  end

  def stop_task
    return unless @task

    @task.stop
    @task = nil
  end

  def failed(error)
    message = { type: :worker_failed, from: self, error: }
    @supervisor.post message
  end
end

# Supervises workers in a supervisor tree.
class Supervisor < Worker
  attr_reader :workers

  def initialize(supervisor:, id:, level:, blueprint: {})
    super
    @workers = {}
    @messages = Async::Queue.new
    setup
  end

  def setup(ids = @blueprint.keys)
    missing = ids - @workers.keys
    add = {}
    missing.each { |id| add[id] = create_worker(id) }
    @workers.merge add
    add.values
  end

  def create_worker(id)
    return unless @workers[id].nil?

    settings = @blueprint[id]
    return unless settings

    @workers[id] = settings[:class].new(blueprint: settings[:workers],
                                        supervisor: self, id:, level: @level + 1)
  end

  def do_task
    run_workers
    fetch_post
  end

  def fetch_post
    Async { loop { receive @messages.dequeue } }
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
    @workers.delete workers
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
      restart_all_for_one worker
    when :rest_for_one
      restart_rest_for_one worker
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

# A root level supervisor
class App < Supervisor
  attr_reader :workers

  def initialize(blueprint: {})
    super blueprint:, id: :app, supervisor: nil, level: 0
  end

  def failed(_error)
    delete_workers
    stop
  end
end

# Our worker class
class Animal < Worker
  def do_task
    loop do
      sleep rand(1..10) * 0.01
      raise 'died!' if rand(3).zero?
    end
  end
end

# Out supervisor class
class Place < Supervisor
  def do_task
    super
    loop do
      sleep rand(1..10) * 0.01
      raise 'burned!' if rand(3).zero?
    end
  end
end

# Our main app class
class AnimalApp < App
  @blueprint = {
    zoo: { class: Place, strategy: :all_for_one, workers: {
      monkey: { class: Animal, strategy: :all_for_one },
      tiger: { class: Animal, strategy: :rest_for_one },
      rhino: { class: Animal, strategy: :one_for_one }
    } },
    farm: { class: Place, strategy: :rest_for_one, workers: {
      cow: { class: Animal, strategy: :all_for_one },
      goat: { class: Animal, strategy: :rest_for_one },
      horse: { class: Animal, strategy: :one_for_one }
    } },
    house: { class: Place, strategy: :one_for_one, workers: {
      cat: { class: Animal, strategy: :all_for_one },
      dog: { class: Animal, strategy: :rest_for_one },
      hamster: { class: Animal, strategy: :one_for_one }
    } }
  }
end

begin
  app = AnimalApp.new(blueprint: AnimalApp.instance_variable_get(:@blueprint))
  Async { app.run }
  # worker = app.dig(:farm, :horse)
  # worker.log 'fail'
  # worker.fail RuntimeError.new('bah')
  # sleep 0.1
  # puts app.hierarchy
rescue Interrupt
  puts
  puts 'hierarchy:'
  puts app.hierarchy
end
