module RSMP
  class Component
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

    def initialize node:, id:, grouped:
      @c_id = id
      @node = node
      @grouped = grouped
      @alarms = {}
      @statuses = {}
      clear_aggregated_status
    end

    def clear_aggregated_status
      @aggregated_status = []
      @aggregated_status_bools = Array.new(8,false)
      @aggregated_status_bools[5] = true
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
 
    def alarm code:, status:
    end

    def log str, options
      @node.log str, options
    end

    def handle_command command_code, arg
      raise UnknownCommand.new "Command #{command_code} not implemented by #{self.class}"
    end

    def get_status status_code, status_name=nil
      raise UnknownStatus.new "Status #{status_code}/#{status_name} not implemented by #{self.class}"
    end

  end
end