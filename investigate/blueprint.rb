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

      log @level.to_s
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

blueprint = {
  zoo: { class: Place, strategy: :all_for_one, nodes: {
    rhino: { class: Animal, strategy: :all_for_one },
    tiger: { class: Animal, strategy: :rest_for_one },
    monkey: { class: Animal, strategy: :one_for_one }
  } },
  farm: { class: Place, strategy: :rest_for_one, nodes: {
    horse: { class: Animal, strategy: :all_for_one },
    cow: { class: Animal, strategy: :rest_for_one },
    goat: { class: Animal, strategy: :one_for_one }
  } },
  house: { class: Place, strategy: :one_for_one, nodes: {
    dog: { class: Animal, strategy: :all_for_one },
    cat: { class: Animal, strategy: :rest_for_one },
    hamster: { class: Animal, strategy: :one_for_one }
  } }
}

app = App.new(blueprint:)
begin
  Async do
    app.run
  end
rescue Interrupt
  puts
end
pp app.hierarchy
