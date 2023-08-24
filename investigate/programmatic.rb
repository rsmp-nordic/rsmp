# frozen_string_literal: true

require_relative 'animals'

app = App.new
zoo = Supervisor.new(id: :zoo1, supervisor: app, worker_class: Place, strategy: :all_for_one)
Node.new(id: :rhino1, supervisor: zoo, worker_class: Animal, strategy: :all_for_one)
Node.new(id: :tiger2, supervisor: zoo, worker_class: Animal, strategy: :rest_for_one)
Node.new(id: :monkey3, supervisor: zoo, worker_class: Animal, strategy: :one_for_one)
farm = Supervisor.new(id: :farm2, supervisor: app, worker_class: Place, strategy: :rest_for_one)
Node.new(id: :horse1, supervisor: farm, worker_class: Animal, strategy: :all_for_one)
Node.new(id: :cow2, supervisor: farm, worker_class: Animal, strategy: :rest_for_one)
Node.new(id: :goat3, supervisor: farm, worker_class: Animal, strategy: :one_for_one)
house = Supervisor.new(id: :house3, supervisor: app, worker_class: Place, strategy: :one_for_one)
Node.new(id: :dog1, supervisor: house, worker_class: Animal, strategy: :all_for_one)
Node.new(id: :cat2, supervisor: house, worker_class: Animal, strategy: :rest_for_one)
Node.new(id: :hamster3, supervisor: house, worker_class: Animal, strategy: :one_for_one)

begin
  Async do
    app.run
  end
rescue Interrupt
  puts
end
pp app.hierarchy
