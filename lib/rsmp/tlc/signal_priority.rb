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

  def prune?
    @state == 'stale' || @state == 'completed'
  end

  def cancel
    if @state == 'activated'
      set_state 'completed'
    end
  end

  def set_state state
    @state = state
    @updated = node.clock.now
    @node.signal_priority_changed self, @state
  end

  def timer
    @age = @node.clock.now - @updated
    case @state
    when 'received'
      if @age >= 0.5
        @node.log "Priority request #{@id} activated.", level: :info
        set_state 'activated'
      end
    when 'activated'
      if @age >= 1
        @node.log "Priority request #{@id} became stale.", level: :info
        set_state 'stale'
      end
    end
  end
end