module RSMP
  # Class for waiting for specific command responses
  class AlarmCollector < Collector
    def initialize proxy,options={}
      @query = options[:query] || {}
      super proxy, options.merge(
        type: 'Alarm',
        title:'alarm'
      )
    end

    def type_match? message
      return false if super(message) == false

      # match fixed attributes
      %w{aCId aSp ack aS sS cat pri}.each do |key|
        want = @query[key]
        got = message.attribute(key)
        case want
        when Regexp
          return false if got !~ want
        when String
          return false if got != want
        end
      end

      # match rvs items
      if @query['rvs']
        query_rvs = @query['rvs']
        message_rvs = message.attributes['rvs']
        return false unless message_rvs
        return false unless query_rvs.all? do |query_item|
          return false unless message_rvs.any? do |message_item|
            next message_item['n'] == query_item['n'] && message_item['v'] == query_item['v']
          end
          next true
        end
      end
      true
    end
  end
end