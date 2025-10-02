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
      message.attribute('sS').each do |item|
        check_status_item_for_repeats(item, subscription_list)
      end
    end

    def check_status_item_for_repeats(item, subscription_list)
      status_code = item['sCI']
      status_name = item['n']
      return if update_rate_set?(subscription_list, status_code, status_name)
      return unless should_check_repeats?(subscription_list, status_code, status_name)

      new_values = { 's' => item['s'], 'q' => item['q'] }
      old_values = @statuses.dig(status_code, status_name)
      raise RSMP::RepeatedStatusError, "no change for #{status_code} '#{status_name}'" if new_values == old_values
    end

    def update_rate_set?(subscription_list, status_code, status_name)
      urt = subscription_list.dig(c_id, status_code, status_name, 'uRt')
      urt.to_i.positive?
    end

    def should_check_repeats?(subscription_list, status_code, status_name)
      soc = subscription_list.dig(c_id, status_code, status_name, 'sOc')
      return false if soc == false
      return false if @allow_repeat_updates[status_code]&.include?(status_name)

      true
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
  end
end
