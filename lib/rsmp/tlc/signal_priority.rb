class RSMP::TLC::SignalPriority
  attr_reader :state, :node, :id, :level, :eta, :vehicleType, :age, :updated

  def initialize node:, id:, level:, eta:, vehicleType:
    @node = node
    @id = id
    @level = level
    @eta = eta
    @vehicleType = vehicleType
    set_state 'received'
  end

  def set_state state
    @state = state
    @updated = node.clock.now
    node.signal_priority_changed self, @state
  end

  def timer
    @age = @node.clock.now - @updated
    case @state
    when 'received'
      set_state 'activated' if @age >= 0.5
    when 'activated'
      set_state 'completed' if @age >= 0.5
    end
  end
end