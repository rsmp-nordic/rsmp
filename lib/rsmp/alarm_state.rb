module RSMP

  # The state of an alarm on a component.
  # The alarm state is for a particular alarm code,
  # a component typically have an alarm state for each
  # alarm code that is defined for the component type.

  class AlarmState
    attr_reader :component_id, :code, :acknowledged, :suspended, :active, :timestamp, :category, :priority, :rvs

    def self.create_from_message component, message
      self.new(
        component: component,
        code: message.attribute("aCId"),
        timestamp: RSMP::Clock.parse(message.attribute('aTs')),
        acknowledged: message.attribute('ack') == 'Acknowledged',
        suspended: message.attribute('aS') == 'Suspended',
        active: message.attribute('sS') == 'Active',
        category: message.attribute('cat'),
        priority: message.attribute('pri').to_i,
        rvs: message.attribute('rvs')
      )
    end

    def initialize component:, code:, 
        suspended: false, acknowledged: false, active: false, timestamp: nil,
        category: 'D', priority: 2, rvs: []
      @component = component
      @component_id = component.c_id
      @code = code
      @suspended = !!suspended
      @acknowledged = !!acknowledged 
      @active = !!active
      @timestamp =  timestamp
      @category = category || 'D'
      @priority = priority || 2
      @rvs = rvs
    end

    def to_hash
      {
        'cId' => @component_id,
        'aCId' => @code,
        'aTs' => Clock.to_s(@timestamp),
        'ack' => (@acknowledged ? 'Acknowledged' : 'notAcknowledged'),
        'sS' => (@suspended ? 'Suspended' : 'notSuspended'),
        'aS' => (@active ? 'Active' : 'inActive'),
        'cat' => @category,
        'pri' => @priority.to_s,
        'rvs' => @rvs
      }
    end

    def acknowledge
      change, @acknowledged = !@acknowledged, true
      update_timestamp if change
      change
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

    # according to the rsmp core spec, the only time an alarm changes to unanknowledged,
    # is when it's activated. See:
    # https://rsmp-nordic.org/rsmp_specifications/core/3.2.0/applicability/basic_structure.html#alarm-status
    def activate
      change, @active, @acknowledged = !@active, true, false
      update_timestamp if change
      change
    end

    def deactivate
      change, @active = @active, false
      update_timestamp if change
      change
    end
    
    def update_timestamp
      @timestamp = @component.now
    end

    def differ_from_message? message
      return true if RSMP::Clock.to_s(@timestamp) != message.attribute('aTs')
      return true if message.attribute('ack') && @acknowledged != (message.attribute('ack').downcase == 'acknowledged')
      return true if message.attribute('sS') && @suspended != (message.attribute('sS').downcase == 'suspended')
      return true if message.attribute('aS') && @active != (message.attribute('aS').downcase == 'active')
      return true if message.attribute('cat') && @category != message.attribute('cat')
      return true if message.attribute('pri') && @priority != message.attribute('pri').to_i
      #return true @rvs = message.attribute('rvs')
      false
    end

    def clear_timestamp
      @timestamp = nil
    end

    def older_message? message
      return false if @timestamp == nil
      RSMP::Clock.parse(message.attribute('aTs')) < @timestamp
    end

    # update from rsmp message
    # component id, alarm code and specialization are not updated
    def update_from_message message
      unless differ_from_message? message
        raise RepeatedAlarmError.new("no changes from previous alarm #{message.m_id_short}")
      end
      if older_message? message
        raise TimestampError.new("timestamp is earlier than previous alarm #{message.m_id_short}")
      end
    ensure
      @timestamp = RSMP::Clock.parse message.attribute('aTs')
      @acknowledged = message.attribute('ack') == 'True'
      @suspended = message.attribute('sS') == 'True'
      @active = message.attribute('aS') == 'True'
      @category = message.attribute('cat')
      @priority = message.attribute('pri').to_i
      @rvs = message.attribute('rvs')
    end
  end
end
