module RSMP

  # A proxy to a remote RSMP component.

  class ComponentProxy < ComponentBase
    def initialize node:, id:, grouped: false
      super
      @statuses = {}
      @allow_repeat_updates = {}
    end

    # allow the next status update to be a repeat value
    def allow_repeat_updates subscribe_list
      subscribe_list.each do |item|
        sCI = item['sCI']
        n = item['n']
        @allow_repeat_updates[sCI] ||= Set.new  # Set is like an array, but with no duplicates
        @allow_repeat_updates[sCI] << n
      end
    end

    # Check that were not receiving repeated update values.
    # The check is not performed for item with an update interval.
    def check_repeat_values message, subscription_list
      message.attribute('sS').each do |item|
        sCI, n, s, q = item['sCI'], item['n'], item['s'], item['q']
        uRt = subscription_list.dig(c_id,sCI,n,'uRt')
        next if uRt.to_i > 0
        next if @allow_repeat_updates[sCI] && @allow_repeat_updates[sCI].include?(n)
        new_values = {'s'=>s,'q'=>q}
        old_values = @statuses.dig(sCI,n)
        if new_values == old_values
          raise RSMP::RepeatedStatusError.new "no change for #{sCI} '#{n}'"
        end
      end
    end
        # Store the latest status update values
    def store_status message
      message.attribute('sS').each do |item|
        sCI, n, s, q = item['sCI'], item['n'], item['s'], item['q']
        @statuses[sCI] ||= {}
        @statuses[sCI][n] = {'s'=>s,'q'=>q}

        # once a value is received, don't allow the value to be a repeat
        @allow_repeat_updates[sCI].delete(n) if @allow_repeat_updates[sCI]
      end
    end
 
    # handle incoming alarm
    def handle_alarm message
#      code = message.attribute('aCId')
#      previous = @alarms[code]
#      if previous
#        unless message.differ?(previous)
#          raise RepeatedAlarmError.new("no changes from previous alarm #{previous.m_id_short}")
#        end
#        if Time.parse(message.attribute('aTs')) < Time.parse(previous.attribute('aTs'))
#          raise TimestampError.new("timestamp is earlier than previous alarm #{previous.m_id_short}")
#        end
#      end
#      p message
#    ensure
#      @alarms[code] = message
    end

 end
end
