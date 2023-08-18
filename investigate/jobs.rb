require 'async'
require 'async/notification'
require 'async/queue'


class Child
	attr_reader :id
	def initialize supervisor:nil, id:nil
		@id = id
		@supervisor = supervisor
		@task = nil
		setup
	end

	def log str
		puts "#{id}: #{str}"
	end

	def setup
	end

	def start
		log 'start'
		@task = Async do |task|
			task.annotate(@id)
			action	
		rescue StandardError => error
			fail error
		end
		self
	end

	def stop
		if @task
			log 'stop'
			@task.stop
			@task = nil
		end
	end

	def fail error
		@supervisor.child_failed self, error
	end
end

class Supervisor < Child
	@@blueprint = {}

	def initialize supervisor:nil, id: :root
		@children = {}
		super supervisor: supervisor, id: id
	end

 	def setup
		@@blueprint.each_pair do |id, settings|
			add_child id, settings
		end
	end

	def action
		@children.values.each do |child|
			child.start
		end
	end

	def add_child id, settings
		child = settings[:class].new supervisor: self, id: id
		@children[id] = child
	end

	def settings_for id
		@@blueprint[id]
	end

	def stop_children
		while item = @children.shift
			id = item.first
			child = item.last
			child.stop
		end
	end

	def stop
		stop_children
		super
	end

	def fail error
		stop_children
		if @supervisor
			super
		else
			puts "root #{id} failed: #{error.inspect}"
			stop
		end
	end

	def child_failed child, error
		id = child.id
		settings = settings_for(id)
		strategy = settings[:strategy]
		puts "#{id} failed: #{error.inspect}, strategy: #{strategy}"
 		@children.delete id
		case strategy
		when :one_for_one
			child = add_child(id, settings_for(id))
			child.start
		when :all_for_one
		end
	end
end


class Timer < Child
	def action
		loop do
			sleep 0.3
			log 'tick'
			raise 'oh no!' if rand(3)==0
		end
	end
end

class App < Supervisor
	@@blueprint = {
		timer1: {class: Timer, strategy: :one_for_one},
		timer2: {class: Timer, strategy: :one_for_one}
	}

	def action
		super
		sleep 1
		raise 'bad super'
	end
end

Async do
	app = App.new.start
end