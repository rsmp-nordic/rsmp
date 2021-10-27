module RSMP
  # Class for waiting for specific command responses
  class CommandResponseMatcher < Matcher
    def initialize proxy, want, options={}
      super proxy, want, options.merge(
        type: ['CommandResponse','MessageNotAck'],
        title:'command response'
      )
    end

    def build_query want
      CommandQuery.new want
    end

    # Get items, in our case the return values
    def get_items message
      message.attributes['rvs']
    end
  end

  # Base class for waiting for status updates or responses
  class StatusUpdateOrResponseMatcher < Matcher
    def initialize proxy, want, options={}
      super proxy, want, options.merge
    end

    def build_query want
      StatusQuery.new want
    end

    # Get items, in our case status values
    def get_items message
      message.attributes['sS']
    end
  end

  # Class for waiting for specific status responses
  class StatusResponseMatcher < StatusUpdateOrResponseMatcher
    def initialize proxy, want, options={}
      super proxy, want, options.merge(
        type: ['StatusResponse','MessageNotAck'],
        title: 'status response'
      )
    end
  end

  # Class for waiting for specific status responses
  class StatusUpdateMatcher < StatusUpdateOrResponseMatcher
    def initialize proxy, want, options={}
      super proxy, want, options.merge(
        type: ['StatusUpdate','MessageNotAck'],
        title:'status update'
      )
    end
  end

  # Class for waiting for an aggregated status response
  class AggregatedStatusMatcher < Collector
    def initialize proxy, options={}
      required = { type: ['AggregatedStatus','MessageNotAck'], title: 'aggregated status' }
      super proxy, options.merge(required)
    end
  end
end