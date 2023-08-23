# frozen_string_literal: true

require_relative 'node'

# Supervises nodes in a supervisor tree.
class Supervisor < Node
  attr_reader :nodes

  # Create supervisor
  def initialize(id:, strategy:, supervisor: nil, blueprint: nil, worker_class: nil)
    super
    @nodes = {}
    @messages = Async::Queue.new
    build(blueprint) if blueprint
  end

  # Build nodes according to blueprint
  def build(blueprint)
    missing = blueprint.keys - @nodes.keys
    add = {}
    missing.each { |id| add[id] = build_node(id, blueprint) }
    @nodes.merge add
    add.values
  end

  # Build a node in a blueprint
  def build_node(id, blueprint)
    return unless @nodes[id].nil?

    settings = blueprint[id]
    return unless settings

    (settings[:nodes] ? Supervisor : Node).new(
      id:,
      supervisor: self,
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

  # Run supervisor by watch for post,
  # and run our own worker and our nodes.
  def run
    watch_messages
    super if @worker_class
    run_nodes
  end

  # Fetch post in an async task by waiting for messages
  # in our post queue.
  def watch_messages
    Async { loop { receive @messages.dequeue } }
  end

  # A messages was receive from our post queue
  # Call the appropriate method, depending on the message type.
  def receive(message)
    case message[:type]
    when :node_failed
      node_failed message[:from], message[:error]
    else
      log "unhandled #{message[:type].inspect}"
    end
  end

  # Run nodes.
  def run_nodes(nodes = @nodes.values)
    nodes.each(&:run)
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
    log 'stop'
    stop_nodes
    stop_worker
  end

  # We failed.
  # Delete our nodes, and then report the error to
  # our supervisor higher up the tree.
  def failed(error)
    delete_nodes
    report_error(error)
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

  # Build string showing supervisor tree
  def hierarchy
    @nodes.transform_values(&:hierarchy)
  end
end
