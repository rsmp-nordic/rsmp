# frozen_string_literal: true

require_relative 'node'

# An app is a root node
class App < Node
  # Create app
  def initialize(blueprint: nil)
    super(blueprint:, id: :app, supervisor: nil, worker_class: nil, strategy: :one_for_one)
  end

  # The app should never fail.
  # If it does, delete all nodes and stop.
  def failed(_error)
    delete_nodes
    stop
  end
end
