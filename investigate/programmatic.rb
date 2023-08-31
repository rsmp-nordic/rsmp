# frozen_string_literal: true

require_relative 'animals'

app = App.new
zoo = Node.new(id: :zoo1, supervisor: app, worker_class: Place, strategy: :all_for_one)
Node.new(id: :rhino1, supervisor: zoo, worker_class: Animal, strategy: :all_for_one)

begin
  Async do
    app.run
  end
rescue Interrupt
  puts
end
