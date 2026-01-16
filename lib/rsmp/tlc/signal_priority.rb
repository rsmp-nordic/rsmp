module RSMP
  module TLC
    # Representation of a priority request for a TLC signal.
    class SignalPriority
      attr_reader :state, :node, :id, :level, :eta, :vehicle_type, :age, :updated

      def initialize(node:, id:, level:, eta:, vehicle_type:)
        @node = node
        @id = id
        @level = level
        @eta = eta
        @vehicle_type = vehicle_type
        self.state = 'received'
      end

      def prune?
        @state == 'stale' || @state == 'completed'
      end

      def cancel
        return unless @state == 'activated'

        self.state = 'completed'
      end

      def state=(state)
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
            self.state = 'activated'
          end
        when 'activated'
          if @age >= 1
            @node.log "Priority request #{@id} became stale.", level: :info
            self.state = 'stale'
          end
        end
      end
    end
  end
end
