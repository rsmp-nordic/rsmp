module RSMP
  # Base class for waiting for status updates or responses
  class StatusCollector < StateCollector
    def initialize proxy, want, options={}
      type = []
      type << 'StatusUpdate' unless options[:updates] == false
      type << 'StatusResponse' unless options[:reponses] == false

      super proxy, want, options.merge(
        title: 'status response',
        filter: RSMP::Filter.new(ingoing: true, outgoing: false, type: type)
      )
    end

    def build_matcher want
      RSMP::StatusMatcher.new want
    end

    # Get items, in our case status values
    def get_items message
      message.attributes['sS'] || []
    end
  end
end