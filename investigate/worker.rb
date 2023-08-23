# frozen_string_literal: true

# Handles actual work.
class Worker
  # Create worker
  def initialize(node)
    @node = node
  end

  # Log, by passing to worker.
  def log(str)
    @node.log str
  end

  # Do actual work.
  def run; end

  # Stop any ongoing work.
  def stop; end

  # We failed with uncaught error
  def fail(error); end
end
