# frozen_string_literal: true

require_relative 'animals'

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
