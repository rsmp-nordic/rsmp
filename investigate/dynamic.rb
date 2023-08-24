# frozen_string_literal: true

require_relative 'animals'

app = App.new
zoo = Supervisor.new(id: :zoo, supervisor: app, worker_class: Place, strategy: :all_for_one)

begin
  Async do
    app.run

    loop do
      sleep 0.1
      if rand(2).zero?
        node = zoo.nodes.values.sample
        if node
          zoo.delete_nodes [].compact
        end
      else
        types = [:tiger,:camel,:buffalo,:parrot,:eagle,:zebra,:snake,:pinguin]
        type = (types - zoo.nodes.keys).sample
        if type
          strategy = [:one_for_all, :rest_for_all, :all_for_one].sample
          Node.new(id: type, supervisor: zoo, worker_class: Animal, strategy: strategy).run
        end
      end    
    end

  end
rescue Interrupt
  puts
end
pp app.hierarchy

   