# frozen_string_literal: true

require_relative 'supervisor'

# An app is the root supervisor
class App < Supervisor
  attr_reader :workers

  # Create app
  def initialize(blueprint:)
    super blueprint:, id: :app, supervisor: nil, level: 0
  end

  # The app should never fail.
  # If it does, we delete all workers, and stop.
  def failed(_error)
    delete_workers
    stop
  end
end
