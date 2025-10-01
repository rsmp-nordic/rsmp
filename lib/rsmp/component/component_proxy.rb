module RSMP
  # A proxy to a remote RSMP component.
  class ComponentProxy < ComponentBase
    def initialize(node:, id:, ntsoid: nil, xnid: nil, grouped: false)
      super
      @alarms = {}
      @statuses = {}
      @allow_repeat_updates = {}
    end

    # allow the next status update to be a repeat value
    def allow_repeat_updates(subscribe_list)
      subscribe_list.each do |item|
        sci = item['sCI']
        n = item['n']
        @allow_repeat_updates[sci] ||= Set.new # Set is like an array, but with no duplicates
        @allow_repeat_updates[sci] << n
      end
    end

    # Check that were not receiving repeated update values.
    # The check is not performed for item with an update interval.
    def check_repeat_values(message, subscription_list)
      component_id = message.attribute('cId')

      message.attribute('sS').each do |item|
        status_code_id = item['sCI']
        status_name = item['n']
        next if repeat_allowed?(subscription_list, component_id, status_code_id, status_name)

        raise_if_repeated(status_code_id, status_name, item)
      end
    end

    # Store the latest status update values
    def store_status(message)
      message.attribute('sS').each do |item|
        sci = item['sCI']
        n = item['n']
        s = item['s']
        q = item['q']
        @statuses[sci] ||= {}
        @statuses[sci][n] = { 's' => s, 'q' => q }

        # once a value is received, don't allow the value to be a repeat
        @allow_repeat_updates[sci]&.delete(n)
      end
    end

    # handle incoming alarm
    def handle_alarm(message)
      code = message.attribute('aCId')
      alarm = get_alarm_state code
      alarm.update_from_message message
    end

    private

    def repeat_allowed?(subscription_list, component_id, status_code_id, status_name)
      update_interval?(subscription_list, component_id, status_code_id, status_name) ||
        suppressed_on_change?(subscription_list, component_id, status_code_id, status_name) ||
        allow_repeat?(status_code_id, status_name)
    end

    def update_interval?(subscription_list, component_id, status_code_id, status_name)
      subscription_list
        .dig(component_id, status_code_id, status_name, 'uRt')
        .to_i
        .positive?
    end

    def suppressed_on_change?(subscription_list, component_id, status_code_id, status_name)
      subscription_list.dig(component_id, status_code_id, status_name, 'sOc') == false
    end

    def allow_repeat?(status_code_id, status_name)
      @allow_repeat_updates[status_code_id]&.include?(status_name)
    end

    def raise_if_repeated(status_code_id, status_name, item)
      new_values = item.slice('s', 'q')
      old_values = @statuses.dig(status_code_id, status_name)
      return unless new_values == old_values

      raise RSMP::RepeatedStatusError, "no change for #{status_code_id} '#{status_name}'"
    end
  end
end
