module RSMP
  # Class for waiting for an aggregated status response
  class AggregatedStatusCollector < Collector
    def initialize(proxy, options = {})
      super(proxy, options.merge(
        filter: RSMP::Filter.new(ingoing: true, outgoing: false, type: 'AggregatedStatus'),
        title: 'aggregated status'
      ))
    end
  end
end
