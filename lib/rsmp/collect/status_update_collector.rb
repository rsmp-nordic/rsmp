module RSMP
  # Class for waiting for specific status responses
  class StatusUpdateCollector < StatusUpdateOrResponseCollector
    def initialize proxy, want, options={}
      super proxy, want, options.merge(
        type: ['StatusUpdate','MessageNotAck'],
        title:'status update'
      )
    end
  end
end