# RSMP Alarm. Manages the various states an alarm can be in.

module RSMP
  class AlarmHandler
    attr_reader :code, :blocked, :suspended, :acknowledged

    def initialize message
      @code = message.attribute('aCId')
      @active =  message.attribute('aS')
      @suspended = (message.attribute('sS') == 'suspended')
      @acknowledged = (message.attribute('ack') == 'Acknowledged')
      @category = message.attribute('cat')
      @priority = message.attribute('pri')
      @timestamp = message.attribute('aTs')
    end

    def handle message
      new_active =  message.attribute('aS')
      new_suspended = (message.attribute('sS') == 'suspended')
      new_acknowledged = (message.attribute('ack') == 'Acknowledged')
      new_category = message.attribute('cat')
      new_priority = message.attribute('pri')
      new_timestamp = message.attribute('aTs')

#      p [@active, @suspended, @acknowledged, @category, @priority, @timestamp]
#      p new_timestamp != @timestamp
      changed = true if new_active != @active ||
                        new_suspended != @suspended ||
                        new_acknowledged != @acknowledged ||
                        new_category != @category ||
                        new_priority != @priority ||
                        new_timestamp != @timestamp

      @active = new_active
      @suspended = new_suspended
      @acknowledged = new_acknowledged
      @category = new_category
      @priority = new_priority
      @timestamp = new_timestamp

      return changed
    end

  end
end