module RSMP

  # Filter messages based on type, direction and component id.
  # Used by Collectors.
  class Filter

    attr_reader :ingoing, :outgoing, :type, :component

    def initialize ingoing:true, outgoing:true, type:nil, component:nil
      @ingoing = ingoing
      @outgoing = outgoing
      @type = type ? [type].flatten : nil
      @component = component
    end

    # Check a message against our match criteria
    # Return true if there's a match, false if not
    def accept? message
      return false if message.direction == :in && @ingoing == false
      return false if message.direction == :out && @outgoing == false
      if @type
        unless message.is_a?(MessageNotAck)
          return false unless @type.include? message.type
        end
      end
      if @component
        return false if message.attributes['cId'] && message.attributes['cId'] != @component
      end
      true
    end

    def reject? message
      !accept? message
    end
  end
end