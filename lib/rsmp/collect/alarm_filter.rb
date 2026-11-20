module RSMP
  # Select alarm attributes and optional return-value items.
  class AlarmFilter < ItemFilter
    ITEMS = { 'Alarm' => 'rvs' }.freeze
    MATCHER = AlarmMatcher
    ENUM_ATTRIBUTES = %w[aSp ack aS sS cat pri].freeze

    def initialize(attributes: {}, **)
      @attributes = attributes
      super(**)
    end

    def describe
      @attributes.empty? ? super : "#{super} #{@attributes}"
    end

    private

    def content_matches?(message)
      super && fixed_attributes_match?(message) && literal_return_values_match?(message)
    end

    def fixed_attributes_match?(message)
      %w[cId aCId aSp ack aS sS cat pri].all? do |key|
        want = @attributes[key]
        got = message.attributes[key]
        case want
        when Regexp then got =~ want
        when String then ENUM_ATTRIBUTES.include?(key) ? want.casecmp?(got) : want == got
        else true
        end
      end
    end

    # Keep the legacy AlarmCollector rvs criteria literal, including false/nil
    # values. Matcher-based all:/any: constraints are evaluated separately.
    def literal_return_values_match?(message)
      wanted = @attributes['rvs']
      return true unless wanted
      return false unless message.attributes['rvs']

      wanted.all? do |want|
        items(message).any? { |item| item['n'] == want['n'] && item['v'] == want['v'] }
      end
    end
  end
end
