module RSMP
  # Shared implementation for message-family filters. Expectations apply to one
  # message and do not change the state kept by a collector's matchers.
  class ItemFilter < Filter
    attr_reader :matchers

    def initialize(type: nil, all: nil, any: nil, **)
      types = type.nil? ? self.class::ITEMS.keys : Array(type)
      raise ArgumentError, "Unsupported message type for #{self.class}" unless (types - self.class::ITEMS.keys).empty?

      configure_matchers(all, any)
      super(type: types, **)
    end

    def accept?(message)
      return false unless super
      # Rejections must reach the consumer even though they have no family items.
      return true if message.is_a?(MessageNotAck)

      content_matches?(message)
    end

    def items(message)
      key = self.class::ITEMS[message.type]
      key ? message.attributes[key] || [] : []
    end

    def describe
      description = super
      description += " #{@match_mode.to_s.delete_suffix('?')} #{@matchers.map(&:want)}" if @matchers
      description
    end

    private

    def configure_matchers(all, any)
      raise ArgumentError, 'Specify all: or any:, not both' unless all.nil? || any.nil?

      @match_mode = all.nil? ? :any? : :all?
      @matchers = all.nil? ? any : all
      return if @matchers.nil?

      unless @matchers.is_a?(Array) && !@matchers.empty? &&
             @matchers.all?(self.class::MATCHER)
        raise ArgumentError, "Expected a nonempty array of #{self.class::MATCHER} instances"
      end

      @matchers = @matchers.dup.freeze
    end

    def content_matches?(message)
      return true unless @matchers

      candidates = items(message)
      @matchers.public_send(@match_mode) do |matcher|
        candidates.any? { |item| matcher.match(item) == true }
      end
    end
  end
end
