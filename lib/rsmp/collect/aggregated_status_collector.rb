module RSMP
  # Class for waiting for an aggregated status response
  class AggregatedStatusCollector < Collector
    def initialize proxy, options={}
      required = { type: ['AggregatedStatus','MessageNotAck'], title: 'aggregated status' }
      super proxy, options.merge(required)
    end
  end
end