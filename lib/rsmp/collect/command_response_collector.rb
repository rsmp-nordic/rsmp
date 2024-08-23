module RSMP
  # Class for waiting for specific command responses
  class CommandResponseCollector < StateCollector
    def initialize proxy, want, options={}
      super proxy, want, options.merge(
        filter: RSMP::Filter.new(ingoing: true, outgoing: false, type: 'CommandResponse'),
        title:'command response'
      )
    end

    def build_query want
      CommandQuery.new want
    end

    # Get items, in our case the return values
    def get_items message
      message.attributes['rvs'] || []
    end
  end
end