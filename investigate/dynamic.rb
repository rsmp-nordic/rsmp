# frozen_string_literal: true

require_relative 'app'

# Our worker base
class AppWorker < Worker
  def stop
    log 'stop'
  end

  def fail(error)
    log error
  end
end

# Animal
class Animal < AppWorker
  def run
    log 'run'
    loop do
      sleep rand(1..10) * 0.1
      raise 'stumble!' if rand(10).zero?

      log 'grrr' if rand(2).zero?
    end
  end
end

# Place
class Place < AppWorker
  def run
    log 'open'
    loop do
      sleep rand(1..10) * 0.1
      raise 'fire!' if rand(5).zero?

      log 'party' if rand(5).zero?
    end
  end
end

app = App.new
zoo = Supervisor.new(id: :zoo, supervisor: app, worker_class: Place, strategy: :all_for_one)
Node.new(id: :rhino, supervisor: zoo, worker_class: Animal, strategy: :all_for_one)
Node.new(id: :tiger, supervisor: zoo, worker_class: Animal, strategy: :reset_for_one)
Node.new(id: :monkey, supervisor: zoo, worker_class: Animal, strategy: :one_for_one)
farm = Supervisor.new(id: :farm, supervisor: app, worker_class: Place, strategy: :all_for_one)
Node.new(id: :horse, supervisor: farm, worker_class: Animal, strategy: :all_for_one)
Node.new(id: :cow, supervisor: farm, worker_class: Animal, strategy: :reset_for_one)
Node.new(id: :goat, supervisor: farm, worker_class: Animal, strategy: :one_for_one)
house = Supervisor.new(id: :house, supervisor: app, worker_class: Place, strategy: :all_for_one)
Node.new(id: :dog, supervisor: house, worker_class: Animal, strategy: :all_for_one)
Node.new(id: :cat, supervisor: house, worker_class: Animal, strategy: :reset_for_one)
Node.new(id: :hamster, supervisor: house, worker_class: Animal, strategy: :one_for_one)

begin
  Async do
    app.run
  end
rescue Interrupt
  puts
end
pp app.hierarchy
