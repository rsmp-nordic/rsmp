module RSMP
  # Class for waiting for specific command responses
  class AlarmCollector < Collector
    def initialize proxy, want, options={}
      @want = want
      super proxy, options.merge(
        type: 'Alarm',
        title:'alarm'
      )
    end

    def type_match? message
      return false if super(message) == false
      [:aCId, :aSp, :ack, :aS, :sS, :cat, :pri].each do |key|
        return false if @want[key] && @want[key] != message.attribute(key.to_s)
      end
      true
    end
  end
end