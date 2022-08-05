module RSMP
  # class that tracks the state of an alarm
  class AlarmState
    attr_reader :component_id, :code, :acknowledged, :suspended, :active, :timestamp, :category, :priority, :rvs

    def initialize component:, code:
      @component = component
      @component_id = component.c_id
      @code = code
      @suspended = false
      @acknowledged = false
      @suspended = false
      @active = false
      @timestamp = nil
      @category = 'D'
      @priority = 2
      @rvs = []
    end

    def to_hash
      {
        'cId' => component_id,
        'aCId' => code,
        'aTs' => Clock.to_s(timestamp),
        'ack' => (acknowledged ? 'Acknowledged' : 'notAcknowledged'),
        'sS' => (suspended ? 'suspended' : 'notSuspended'),
        'aS' => (active ? 'Active' : 'inActive'),
        'cat' => category,
        'pri' => priority.to_s,
        'rvs' => rvs
      }
    end
    def suspend
      change, @suspended = !@suspended, true
      update_timestamp if change
      change
    end

    def resume
      change, @suspended = @suspended, false
      update_timestamp if change
      change
    end

    def activate
      change, @active = !@active, true
      update_timestamp if change
      change
    end

    def deactivate
      change, @active = @active, false
      update_timestamp if change
      change
    end
    
    def update_timestamp
      @timestamp = @component.node.clock.now
    end

    def to_message specialization:
      Alarm.new(
        'cId' => @component_id,
        'aSp' => specialization,
        'aCId' => @code,
        'aTs' => Clock.to_s(@timestamp),
        'ack' => (@acknowledged ? 'Acknowledged' : 'notAcknowledged'),
        'sS' => (@suspended ? 'suspended' : 'notSuspended'),
        'aS' => (@active ? 'Active' : 'inActive'),
        'cat' => @category,
        'pri' => @priority.to_s,
        'rvs' => @rvs
      )
    end

    def differ_from_message? message
      return true if @timestamp != message.attribute('aTs')
      return true if message.attribute('ack') && @acknowledged != (message.attribute('ack') == 'True')
      return true if message.attribute('sS') && @suspended != (message.attribute('sS') == 'True')
      return true if message.attribute('aS') && @active != (message.attribute('aS') == 'True')
      return true if message.attribute('cat') && @category != message.attribute('cat')
      return true if message.attribute('pri') && @priority != message.attribute('pri').to_i
      #return true @rvs = message.attribute('rvs')
      false
    end

    # update from rsmp message
    # component id, alarm code and specialization are not updated
    def update_from_message message
      unless differ_from_message? message
        raise RepeatedAlarmError.new("no changes from previous alarm #{message.m_id_short}")
      end
      if Time.parse(message.attribute('aTs')) < Time.parse(message.attribute('aTs'))
        raise TimestampError.new("timestamp is earlier than previous alarm #{message.m_id_short}")
      end
    ensure
      @timestamp = message.attribute('aTs')
      @acknowledged = message.attribute('ack') == 'True'
      @suspended = message.attribute('sS') == 'True'
      @active = message.attribute('aS') == 'True'
      @category = message.attribute('cat')
      @priority = message.attribute('pri').to_i
      @rvs = message.attribute('rvs')
    end
  end
end
