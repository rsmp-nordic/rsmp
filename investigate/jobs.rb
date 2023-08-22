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

 	def setup
 		setup_by_id @blueprint.keys
	end

	def setup_by_id ids
		ids.each do |id|
			create_worker(id) unless @workers[id]
		end
	end			

	def do_task
		run_workers
		handle_post
	end

	def handle_post
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

	def run_workers
		@workers.values.each do |worker|
			worker.run
		end
	end

	def run_workers_by_id ids
		ids.each do |id|
			@workers[id].run
		end
	end

	def create_worker id
		settings = @blueprint[id]
		klass = settings[:class]
		blueprint = settings[:workers]
		#log "create_worker id: #{id}, class: #{klass}, blueprint: #{blueprint}"
		worker = klass.new(blueprint: blueprint, supervisor: self, id: id, level: @level+1 )
		@workers[id] = worker
	end

	def settings_for id
		@blueprint[id]
	end

	def delete_workers
		delete_workers_by_id @blueprint.keys.reverse
	end

	def delete_workers_by_id ids
		ids.each do |id|
			worker = @workers[id]
			worker.stop if worker
			@workers.delete id
		end
	end

	def stop_workers
		stop_workers_by_id @blueprint.keys.reverse
	end

	def stop_workers_by_id ids
		ids.each do |id|
			worker = @workers[id]
			worker.stop if worker
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
		settings = settings_for(id)
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
			setup
			run_workers
		when :rest_for_one
			ids = @blueprint.keys.drop_while {|i| i!=id}
			# failed worker is already stopped, if we call stop, the current code is skipped
			delete_workers_by_id ids.reverse-[id]
			setup_by_id ids
			run_workers_by_id ids
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

class Timer < Worker
	def do_task
		loop do
			sleep (rand(10)+1)*0.1
			#log 'tick'
			raise 'oh no!' if rand(2)==0
		end
	end
end

class Metro < Supervisor
	def do_task
		super
		loop do
			sleep (rand(10)+1)*0.1
			raise 'oh no!' if rand(2)==0
		end
	end
end

class MetroApp < App
	#3.times do |i|
	#	@blueprint["timer_#{i}".to_s] = {class: Timer, strategy: [:rest_for_one,:one_for_all,:all_for_one].sample}
	#end

	def do_task
		super
		#sleep 1; raise 'bad'
	end
end

begin
	Async do
		blueprint = {  
			metro1: { class: Metro, strategy: :all_for_one, workers: {
				timer1_1: { class: Worker, strategy: :all_for_one},
				timer1_2: { class: Worker, strategy: :rest_for_one},
				timer1_3: { class: Worker, strategy: :one_for_one}				
				}
			},
			metro2: { class: Metro, strategy: :rest_for_one, workers: {
				timer2_1: { class: Timer, strategy: :all_for_one},
				timer2_2: { class: Timer, strategy: :rest_for_one},
				timer2_3: { class: Timer, strategy: :one_for_one}				
				}
			},
			metro3: { class: Metro, strategy: :one_for_one, workers: {
				timer3_1: { class: Timer, strategy: :all_for_one},
				timer3_2: { class: Timer, strategy: :rest_for_one},
				timer3_3: { class: Timer, strategy: :one_for_one}				
				}
			}
		}
		app = MetroApp.new(blueprint: blueprint).run
		#worker = app.dig(:metro1, :timer1_1)
		
		#worker.log 'fail'
		#worker.fail RuntimeError.new('bah')
		#sleep 0.1
		#puts app.hierarchy
	end
rescue Interrupt
	puts
end