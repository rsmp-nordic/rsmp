module RSMP
  # Class for waiting for a message acknowledgement
  class AckCollector < Collector
    def initialize proxy, options={}
      raise ArgumentError.new("m_id must be provided") unless options[:m_id]
      required = { type: 'MessageAck', num: 1, title: 'message acknowledgement' }
      super proxy, options.merge(required)
    end

    # Check if we the MessageAck related to initiating request, identified by @m_id.
    def type_match? message
      return false if super(message) == false
      return message.attribute('oMId') == @options[:m_id]
    end
  end
end