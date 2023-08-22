require 'async'
require 'async/queue'

class Worker
  attr_reader :id

  def initialize blueprint:{}, supervisor:nil, id:nil, level:
    @id = id
    @supervisor = supervisor
    @blueprint = blueprint
    @level = level
    @task = nil
  end

  def indent str
    '. '*@level + str
  end

  def log str
    id_str = indent(@id.to_s)
    puts "#{id_str.ljust(20)} #{str}"
  end

  def hierarchy
    me = indent(@id.to_s) + "\n"
  end

  def run
    log 'run'
    @task = Async do |task|
      task.annotate(@id)
      do_task  
    rescue StandardError => error
      log 'fail'
      failed error
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
    if @task
      @task.stop
      @task = nil
    end
  end

  def failed error
    message = {type: :worker_failed, from: self, error: error}
    @supervisor.post message
  end
end

class Supervisor < Worker
  attr_reader :workers

  def initialize blueprint:{}, supervisor:, id:, level:
    super
    @workers = {}
    @messages = Async::Queue.new
    setup
  end

  def setup ids=@blueprint.keys
    workers = []
    ids.each do |id|
      workers << create_worker(id) unless @workers[id]
    end
    workers
  end      

  def create_worker id
    return if @workers[id]
    return unless settings = @blueprint[id]
    @workers[id] = settings[:class].new(
      blueprint: settings[:workers],
      supervisor: self,
      id: id,
      level: @level+1
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

  def receive message
    case message[:type]
    when :worker_failed
      worker_failed message[:from], message[:error]
    else
      log "unhandled #{message[:type].inspect}"
    end
  end

  def run_workers workers=@workers.values
    workers.each do |worker|
      worker.run
    end
  end

  def stop_workers workers=@workers.values.reverse
    workers.each do |worker|
      worker.stop
    end
  end

  def delete_workers workers=@workers.values.reverse
    workers.each do |worker|
      worker.stop
      @workers.delete id
    end
  end

  def stop
    log 'stop'
    stop_workers
    stop_task
  end

  def failed error
    delete_workers
    super
  end

  def post message
    @messages.enqueue(message)
  end

  def worker_failed worker, error
    id = worker.id
    settings = @blueprint[id]
    strategy = settings[:strategy]
    #log "worker #{id.inspect} failed: #{error.inspect}, strategy: #{strategy}"
    case strategy
    when :one_for_one
       @workers.delete id
      worker = create_worker(id)
      worker.run
    when :all_for_one
       @workers.delete id
      delete_workers
      workers = setup
      run_workers workers
    when :rest_for_one
      ids = @blueprint.keys.drop_while {|i| i!=id}
      rest = @workers.select {|id,worker| ids.include?(id)}.values.reverse
      delete_workers rest
      workers  = setup ids
      run_workers workers
    end 
  end

  def hierarchy
    super + @workers.map { |worker| worker[1].hierarchy }.join
  end

  def dig *args
    worker = @workers[args.shift]
    return worker if args.empty?
    return nil unless worker
    worker.dig *args
  end
end

class App < Supervisor
  attr_reader :workers
  
  def initialize blueprint:{}
    super blueprint: blueprint, id: :app, supervisor: nil, level: 0
  end

  def failed error
    delete_workers
    stop
  end
end



# our app

class Animal < Worker
  def do_task
    loop do
      sleep (rand(10)+1)*0.01
      raise 'died!' if rand(2)==0
    end
  end
end

class Place < Supervisor
  def do_task
    super
    loop do
      sleep (rand(10)+1)*0.01
      raise 'burned!' if rand(2)==0
    end
  end
end

class AnimalApp < App
  @blueprint = {  
    zoo: { class: Place, strategy: :all_for_one, workers: {
      monkey: { class: Animal, strategy: :all_for_one},
      tiger: { class: Animal, strategy: :rest_for_one},
      rhino: { class: Animal, strategy: :one_for_one}
      }
    },
    farm: { class: Place, strategy: :rest_for_one, workers: {
      cow: { class: Animal, strategy: :all_for_one},
      goat: { class: Animal, strategy: :rest_for_one},
      horse: { class: Animal, strategy: :one_for_one}
      }
    },
    house: { class: Place, strategy: :one_for_one, workers: {
      cat: { class: Animal, strategy: :all_for_one},
      dog: { class: Animal, strategy: :rest_for_one},
      hamster: { class: Animal, strategy: :one_for_one}
      }
    }
  }

  def do_task
    super
    #sleep 1; raise 'root issues'
  end
end



begin
  app = AnimalApp.new(blueprint: AnimalApp.instance_variable_get(:@blueprint))
  Async { app.run }
  #worker = app.dig(:farm, :horse)
  #worker.log 'fail'
  #worker.fail RuntimeError.new('bah')
  #sleep 0.1
  #puts app.hierarchy
rescue Interrupt
  puts
  puts 'hierarchy:'
  puts app.hierarchy
end