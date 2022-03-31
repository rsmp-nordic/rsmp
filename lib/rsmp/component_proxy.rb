module RSMP

  # A proxy to a remote RSMP component.

  class ComponentProxy < ComponentBase
    def initialize node:, id:, grouped: false
      super
    end

    # Handle an incoming status respone, by storing the values
    def handle_status_response message
      store_status message, check_repeated: false
    end

    # Handle an incoming status update, by storing the values
    def handle_status_update message
      store_status message, check_repeated: true
    end

    # Store the latest status update values, optionally
    # checking that we're not receiving unchanged values if we're subscribed
    # with updates only on change
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
