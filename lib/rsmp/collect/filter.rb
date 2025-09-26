module RSMP
  # Filter messages based on type, direction and component id.
  # Used by Collectors.
  class Filter
    attr_reader :ingoing, :outgoing, :type, :component

    def initialize(ingoing: true, outgoing: true, type: nil, component: nil)
      @ingoing = ingoing
      @outgoing = outgoing
      @type = type ? [type].flatten : nil
      @component = component
    end

    # Check a message against our match criteria
    # Return true if there's a match, false if not
    def accept?(message)
      return false unless direction_matches?(message)
      return false unless type_matches?(message)
      return false unless component_matches?(message)

      true
    end

    private

    def direction_matches?(message)
      return false if message.direction == :in && @ingoing == false
      return false if message.direction == :out && @outgoing == false

      true
    end

    def type_matches?(message)
      return true unless @type
      return true if message.is_a?(MessageNotAck)

      @type.include?(message.type)
    end

    def component_matches?(message)
      return true unless @component
      return true unless message.attributes['cId']

      message.attributes['cId'] == @component
    end

    public

    def reject?(message)
      !accept?(message)
    end
  end
end
