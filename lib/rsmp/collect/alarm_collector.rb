module RSMP
  # Class for waiting for specific command responses
  class AlarmCollector < Collector
    def initialize(proxy, options = {})
      @matcher = options[:matcher] || {}
      super(proxy, options.merge(
        filter: RSMP::Filter.new(ingoing: true, outgoing: false, type: 'Alarm'),
        title: 'alarm'
      ))
    end

    def acceptable?(message)
      return false if super == false
      return false unless fixed_attributes_match?(message)
      return false unless rvs_attributes_match?(message)

      true
    end

    private

    def fixed_attributes_match?(message)
      %w[cId aCId aSp ack aS sS cat pri].each do |key|
        want = @matcher[key]
        got = message.attribute(key)
        case want
        when Regexp
          return false if got !~ want
        when String
          return false if got != want
        end
      end
      true
    end

    def rvs_attributes_match?(message)
      return true unless @matcher['rvs']

      matcher_rvs = @matcher['rvs']
      message_rvs = message.attributes['rvs']
      return false unless message_rvs

      matcher_rvs.all? do |matcher_item|
        message_rvs.any? do |message_item|
          message_item['n'] == matcher_item['n'] && message_item['v'] == matcher_item['v']
        end
      end
    end

    public

    # return a string that describes what we're collecting
    def describe_matcher
      "#{describe_num_and_type} #{{ component: @options[:component] }.merge(@matcher).compact}"
    end
  end
end
