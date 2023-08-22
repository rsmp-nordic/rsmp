# frozen_string_literal: true

require_relative 'app'

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
  worker = app.dig(:farm, :horse)
  worker.log 'fail'
  worker.fail RuntimeError.new('bah')
  # sleep 0.1
  # puts app.hierarchy
rescue Interrupt
  puts
  puts 'hierarchy:'
  puts app.hierarchy
end
