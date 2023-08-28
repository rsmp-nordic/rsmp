# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/queue'
require_relative 'worker'

# Supervises nodes in a node tree.
class Node
  attr_reader :nodes, :id, :strategy, :level, :worker

  # Create node
  def initialize(id:, strategy:, supervisor: nil, blueprint: nil, worker_class: nil)
    @id = id
    @supervisor = supervisor
    @nodes = {}
    @strategy = strategy
    @worker_class = worker_class
    @task = nil
    @level = nil
    @messages = Async::Queue.new
    @failure = Async::Condition.new

    @supervisor&.add_node(self)
    adjust_level
    build(blueprint) if blueprint
  end

 # Reset our level to node level + 1
  def adjust_level
    @level = @supervisor ? @supervisor.level + 1 : 0
  end

  # More readable debug output
  def inspect
    "Node <#{@id}>"
  end

  # Intend a string according to the tree level.
  def indent(str)
    '. ' * @level + str
  end

  # Output a string indented and with our id in front.
  def log(str)
    id_str = indent(@id.to_s)
    puts "#{id_str.ljust(12)} #{str}"
  end

  # Construct worker, using our worker class.
  def create_worker
    @worker = @worker_class.new(self) unless @worker
  end

  # Build nodes according to blueprint
  def build(blueprint)
    add = blueprint.except(@nodes.keys)
    add.transform_values! { |id| build_node(id, blueprint[id]) }
    @nodes.merge add
    add.values
  end

  # Build a node in a blueprint
  def build_node(id, settings)
    return unless @nodes[id].nil?

    return unless settings

    (settings[:nodes] ? Node : Node).new(
      id:,
      node: self,
      worker_class: settings[:class],
      blueprint: settings[:nodes],
      strategy: settings[:strategy]
    )
  end

  # Add a node
  def add_node(node)
    raise "Node #{node.id.inspect} already exists" if @nodes[node.id]

    @nodes[node.id] = node
  end

  # Run our worker inside an async task.
  # Uncaught errors are reported to our node,
  # which can then restart ours (and possible others) worker,
  # depending on our restart strategy.
  def run
    @task = Async do |task|
      task.annotate(@id)
      task { watch_messages }
      task { work }
      run_nodes
      raise @failure.wait

    rescue StandardError => e
      @worker.failed(e) if @worker
      report_error e
    end
  end

  def work
    return unless @worker_class
     
    create_worker
    @worker.run
  end

  def task
    Async do
      yield
    rescue StandardError => e
      @failure.signal e
    end
  end

  # Fetch post in an async task by waiting for messages
  # in our post queue.
  def watch_messages
    loop { receive @messages.dequeue }
  end

  # A messages was receive from our post queue
  # Call the appropriate method, depending on the message type.
  def receive(message)
    case message[:type]
    when :node_failed
      node_failed message[:from], message[:error]
    else
      log "unhandled message #{message[:type].inspect}"
    end
  end

  # Run nodes.
  def run_nodes(nodes = @nodes.values)
    nodes.each(&:run)
  end

  # Stop our worker and the async task it's running in.
  def stop_worker
    @worker&.stop
    @worker = nil
    @task&.stop
    @task = nil
  end

  # Stop nodes.
  def stop_nodes(nodes = @nodes.values.reverse)
    nodes.each(&:stop)
  end

  # Delete nodes, stopping them first.
  def delete_nodes(nodes = @nodes.values.reverse)
    nodes.each(&:stop)
    @nodes = @nodes.except(*@nodes.keys)
  end

  # Stop our nodes and then our worker.
  def stop
    stop_nodes
    stop_worker
  end

  # Report an error to our node.
  def report_error(error)
    message = { type: :node_failed, from: self, error: }
    @supervisor.post message
  end

  # Send us a message
  def post(message)
    @messages.enqueue(message)
  end

  # One of our nodes failed.
  # Restart depending on the node strategy:
  # - one for one:  just the failed node
  # - rest for one: the failed node and nodes specified after it in the blueprint
  # - all for one: all our nodes
  def node_failed(node, _error)
    case node.strategy
    when :one_for_one
      restart_one_for_one node
    when :all_for_one
      restart_all_for_one
    when :rest_for_one
      restart_rest_for_one node
    end
  end

  # Restart node
  def restart_one_for_one(node)
    node.stop
    node.run
  end

  # Restart node and other nodes after it
  def restart_rest_for_one(node)
    nodes = @nodes.values.drop_while { |i| i != node }
    nodes.reverse.each(&:stop)
    nodes.each(&:run)
  end

  # Restart all nodes
  def restart_all_for_one
    @nodes.values.reverse.each(&:stop)
    @nodes.each_value(&:run)
  end

  # Build string showing node tree
  def hierarchy
    @nodes.transform_values(&:hierarchy)
  end
end
