module RSMP
  # Class for waiting for specific status responses
  class StatusResponseCollector < StatusUpdateOrResponseCollector
    def initialize proxy, want, options={}
      super proxy, want, options.merge(
        type: ['StatusResponse','MessageNotAck'],
        title: 'status response'
      )
    end
  end
end