module RSMP
  class Component

    def initialize node:, id:
      @id = id
      @node = node
      @alarms = {}
      @statuses = {}
    end

    def alarm code, status
    end

    def status code, value
    end

  end
end