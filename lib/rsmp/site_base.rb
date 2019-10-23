# Things shared between sites and site proxies

module RSMP
  module SiteBase
    attr_reader :aggregated_status, :aggregated_status_bools

    AGGREGATED_STATUS_KEYS = [ :local_control,
                               :communication_distruption,
                               :high_priority_alarm,
                               :medium_priority_alarm,
                               :low_priority_alarm,
                               :normal,
                               :rest,
                               :not_connected ]

    def initialize_site
      clear_aggregated_status
    end

    def clear_aggregated_status
      @aggregated_status = []
      @aggregated_status_bools = Array.new(8,false)
    end

    def set_aggregated_status status
      status = [:status] if status.is_a? Symbol
      raise InvalidArgument unless status.is_a? Array
      input = status & AGGREGATED_STATUS_KEYS
      if input != @aggregated_status
        AGGREGATED_STATUS_KEYS.each_with_index do |key,index|
          @aggregated_status_bools[index] = status.include?(key)
        end
        aggrated_status_changed
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
        aggrated_status_changed
      end
    end

    def aggrated_status_changed
    end
  end
end