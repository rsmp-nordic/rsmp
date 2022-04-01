module RSMP

  # RSMP component base class.

  class ComponentBase
    include Inspect

    attr_reader :c_id, :node, :alarms, :statuses, :aggregated_status, :aggregated_status_bools, :grouped

    AGGREGATED_STATUS_KEYS = [ :local_control,
                               :communication_distruption,
                               :high_priority_alarm,
                               :medium_priority_alarm,
                               :low_priority_alarm,
                               :normal,
                               :rest,
                               :not_connected ]

    def initialize node:, id:, grouped: false
      @c_id = id
      @node = node
      @grouped = grouped
      @alarms = {}
      clear_aggregated_status
    end

    def clear_aggregated_status
      @aggregated_status = []
      @aggregated_status_bools = Array.new(8,false)
      @aggregated_status_bools[5] = true
    end

    def log str, options
      default = { component: c_id}
      @node.log str, default.merge(options)
    end

    def set_aggregated_status status, options={}
      status = [status] if status.is_a? Symbol
      raise InvalidArgument unless status.is_a? Array
      input = status & AGGREGATED_STATUS_KEYS
      if input != @aggregated_status
        AGGREGATED_STATUS_KEYS.each_with_index do |key,index|
          @aggregated_status_bools[index] = status.include?(key)
        end
        aggregated_status_changed options
      end
    end

    def set_aggregated_status_bools status
      raise InvalidArgument unless status.is_a? Array
      raise InvalidArgument unless status.size == 8
      if status != @aggregated_status_bools
        @aggregated_status = []
        AGGREGATED_STATUS_KEYS.each_with_index do |key,index|
          on = status[index] == true
          @aggregated_status_bools[index] = on
          @aggregated_status << key if on
        end
        aggregated_status_changed
      end
    end

    def aggregated_status_changed options={}
      @node.aggregated_status_changed self, options
    end

  end
end
