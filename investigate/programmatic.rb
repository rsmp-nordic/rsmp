# frozen_string_literal: true

require_relative 'animals'

app = App.new
zoo = Supervisor.new(id: :zoo, supervisor: app, worker_class: Place, strategy: :all_for_one)
Node.new(id: :rhino, supervisor: zoo, worker_class: Animal, strategy: :all_for_one)
Node.new(id: :tiger, supervisor: zoo, worker_class: Animal, strategy: :rest_for_one)
Node.new(id: :monkey, supervisor: zoo, worker_class: Animal, strategy: :one_for_one)
farm = Supervisor.new(id: :farm, supervisor: app, worker_class: Place, strategy: :rest_for_one)
Node.new(id: :horse, supervisor: farm, worker_class: Animal, strategy: :all_for_one)
Node.new(id: :cow, supervisor: farm, worker_class: Animal, strategy: :rest_for_one)
Node.new(id: :goat, supervisor: farm, worker_class: Animal, strategy: :one_for_one)
house = Supervisor.new(id: :house, supervisor: app, worker_class: Place, strategy: :one_for_one)
Node.new(id: :dog, supervisor: house, worker_class: Animal, strategy: :all_for_one)
Node.new(id: :cat, supervisor: house, worker_class: Animal, strategy: :rest_for_one)
Node.new(id: :hamster, supervisor: house, worker_class: Animal, strategy: :one_for_one)

begin
  Async do
    app.run
  end
rscue Interrupt
  puts
end
pp app.hierarchy
