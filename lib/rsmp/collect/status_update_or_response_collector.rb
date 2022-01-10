module RSMP
  # Base class for waiting for status updates or responses
  class StatusUpdateOrResponseCollector < StateCollector
    def initialize proxy, want, options={}
      super proxy, want, options.merge(outgoing: false)
    end

    def build_query want
      RSMP::StatusQuery.new want
    end

    # Get items, in our case status values
    def get_items message
      message.attributes['sS'] || []
    end
  end
end