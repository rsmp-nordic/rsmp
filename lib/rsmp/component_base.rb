module RSMP
  # RSMP component base class.

  class ComponentBase
    include Inspect

    attr_reader :c_id, :ntsOId, :xNId, :node, :alarms, :statuses,
                :aggregated_status, :aggregated_status_bools, :grouped

    AGGREGATED_STATUS_KEYS = %i[local_control
                                communication_distruption
                                high_priority_alarm
                                medium_priority_alarm
                                low_priority_alarm
                                normal
                                rest
                                not_connected].freeze

    def initialize(node:, id:, ntsOId: nil, xNId: nil, grouped: false)
      if grouped == false && (ntsOId || xNId)
        raise RSMP::ConfigurationError, 'ntsOId and xNId are only allowed for grouped objects'
      end

      @c_id = id
      @ntsOId = ntsOId
      @xNId = xNId
      @node = node
      @grouped = grouped
      clear_aggregated_status
      @alarms = {}
    end

    def now
      node.now
    end

    def clear_alarm_timestamps
      @alarms.each_value(&:clear_timestamp)
    end

    def get_alarm_state(alarm_code)
      @alarms[alarm_code] ||= RSMP::AlarmState.new component: self, code: alarm_code
    end

    def clear_aggregated_status
      @aggregated_status = []
      @aggregated_status_bools = Array.new(8, false)
      @aggregated_status_bools[5] = true
    end

    def log(str, options)
      default = { component: c_id }
      @node.log str, default.merge(options)
    end

    def set_aggregated_status(status, options = {})
      status = [status] if status.is_a? Symbol
      raise InvalidArgument unless status.is_a? Array

      input = status & AGGREGATED_STATUS_KEYS
      return unless input != @aggregated_status

      AGGREGATED_STATUS_KEYS.each_with_index do |key, index|
        @aggregated_status_bools[index] = status.include?(key)
      end
      aggregated_status_changed options
    end

    def set_aggregated_status_bools(status)
      raise InvalidArgument unless status.is_a? Array
      raise InvalidArgument unless status.size == 8

      return unless status != @aggregated_status_bools

      @aggregated_status = []
      AGGREGATED_STATUS_KEYS.each_with_index do |key, index|
        on = status[index] == true
        @aggregated_status_bools[index] = on
        @aggregated_status << key if on
      end
      aggregated_status_changed
    end

    def aggregated_status_changed(options = {})
      @node.aggregated_status_changed self, options
    end
  end
end
