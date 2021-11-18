module RSMP

  # Class that represents an RMSP component.
  # Currently this class is used by both SiteProxy and SupervisorProxy, and can
  # therefore represent either a local or remote (proxy) component.

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

    def initialize node:, id:, grouped: false
      @c_id = id
      @node = node
      @grouped = grouped
      @alarms = {}
      @statuses = {}
      @subscribes = {}
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

    def log str, options
      default = { component: c_id}
      @node.log str, default.merge(options)
    end

    def handle_command command_code, arg
      raise UnknownCommand.new "Command #{command_code} not implemented by #{self.class}"
    end

    def get_status status_code, status_name=nil
      raise UnknownStatus.new "Status #{status_code}/#{status_name} not implemented by #{self.class}"
    end

    def handle_alarm message
      code = message.attribute('aCId')
      previous = @alarms[code]
      if previous
        unless message.differ?(previous)
          raise RepeatedAlarmError.new("no changes from previous alarm #{previous.m_id_short}")
        end
        if Time.parse(message.attribute('aTs')) < Time.parse(previous.attribute('aTs'))
          raise TimestampError.new("timestamp is earlier than previous alarm #{previous.m_id_short}")
        end
      end
    ensure
      @alarms[code] = message
    end

    # Handle an incoming status respone, by storing the values
    def handle_status_response message
      store_status message, check_repeated: false
    end

    # Handle an incoming status update, by storing the values
    def handle_status_update message
      store_status message, check_repeated: true
    end

    # Our proxy subscribed to status updates
    # Store update rates, so we can check for repeated alarm if we asked for updates only
    # when there's a change, not on a regular interval.
    # After subscribing, an update status us send regarless of whether values changes,
    # and we store that.
    def handle_status_subscribe status_list
      status_list.each do |item|
        sCI, n, uRt = item['sCI'], item['n'], item['uRt']

        # record the update rate, so we can check for repeated status values if rate is zero
        @subscribes[sCI] ||= {}
        @subscribes[sCI][n] = {'uRt'=>uRt}

        # record that we expect an upeate, even though the value might not change
        @statuses[sCI] ||= {}
        @statuses[sCI][n] ||= {}
        @statuses[sCI][n][:initial] = true
      end
    end

    # Our proxy unsubscribed to status updates.
    # Update our list of update rates.
    def handle_status_unsubscribe status_list
      status_list.each do |item|
        sCI, n = item['sCI'], item['n']
        if @subscribes[sCI]
          @subscribes[sCI].delete n
        end
        if @subscribes[sCI].empty?
          @subscribes.delete sCI
        end

        # remove any mark that would allow the next update to be a repeat
        item = @statuses.dig sCI, n
        item.delete(:initial) if item
      end
    end

    # Store the latest status update values, optionally
    # checking that we're not receiving unchanged values if we're subscribed
    # wit updates only on change
    def store_status message, check_repeated:
      message.attribute('sS').each do |item|
        sCI, n, s, q = item['sCI'], item['n'], item['s'], item['q']
        uRt = @subscribes.dig(sCI,n,'uRt')
        new_values = {'s'=>s,'q'=>q}
        old_values = @statuses.dig(sCI,n)
        if check_repeated && uRt.to_i == 0
          if new_values == old_values
            raise RSMP::RepeatedStatusError.new "no change for #{sCI} '#{n}'"
          end
        end
        @statuses[sCI] ||= {}
        @statuses[sCI][n] = new_values
      end
    end

  end
end