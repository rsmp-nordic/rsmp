module RSMP

  # Filter messages based on type, direction and component id.
  # Used by Collectors.
  class Filter
    def initialize ingoing:true, outgoing:true, type:, component:nil
      @ingoing = ingoing
      @outgoing = outgoing
      @type = type
      @component = component
    end

    # Check a message against our match criteria
    # Return true if there's a match, false if not
    def accept? message
      return false if message.direction == :in && @ingoing == false
      return false if message.direction == :out && @outgoing == false
      if @type
        if @type.is_a? Array
          return false unless @type.include? message.type
        else
          return false unless message.type == @type
        end
      end
      if @component
        return false if message.attributes['cId'] && message.attributes['cId'] != @component
      end
      true
    end
  end
end