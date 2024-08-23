module RSMP
  # Class for waiting for specific command responses
  class AlarmCollector < Collector
    def initialize proxy,options={}
      @matcher = options[:matcher] || {}
      super proxy, options.merge(
        filter: RSMP::Filter.new(ingoing: true, outgoing: false, type: 'Alarm'),
        title:'alarm'
      )
    end

    # match alarm attributes
    def acceptable? message
      return false if super(message) == false

      # match fixed attributes
      %w{cId aCId aSp ack aS sS cat pri}.each do |key|
        want = @matcher[key]
        got = message.attribute(key)
        case want
        when Regexp
          return false if got !~ want
        when String
          return false if got != want
        end
      end

      # match rvs items
      if @matcher['rvs']
        matcher_rvs = @matcher['rvs']
        message_rvs = message.attributes['rvs']
        return false unless message_rvs
        return false unless matcher_rvs.all? do |matcher_item|
          return false unless message_rvs.any? do |message_item|
            next message_item['n'] == matcher_item['n'] && message_item['v'] == matcher_item['v']
          end
          next true
        end
      end
      true
    end

    # return a string that describes what we're collecting
    def describe_matcher
      "#{describe_num_and_type} #{ {component: @options[:component]}.merge(@matcher).compact }"
    end

  end
end