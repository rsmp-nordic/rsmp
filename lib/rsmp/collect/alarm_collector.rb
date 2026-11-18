module RSMP
  # Collect matching alarm messages
  class AlarmCollector < Collector
    ENUM_ATTRIBUTES = AlarmFilter::ENUM_ATTRIBUTES

    def initialize(proxy, options = {})
      @matcher = options[:matcher] || {}
      super(proxy, options.merge(
        filter: AlarmFilter.new(ingoing: true, outgoing: false, attributes: @matcher),
        title: 'alarm'
      ))
    end

    def acceptable?(message)
      message.is_a?(Alarm) && super
    end

    # return a string that describes what we're collecting
    def describe_matcher
      "#{describe_num_and_type} #{{ component: @options[:component] }.merge(@matcher).compact}"
    end
  end
end
