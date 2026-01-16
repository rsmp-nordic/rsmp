module RSMP
  # The state of an alarm on a component.
  # The alarm state is for a particular alarm code,
  # a component typically have an alarm state for each
  # alarm code that is defined for the component type.
  class AlarmState
    attr_reader :component_id, :code, :acknowledged, :suspended, :active, :timestamp, :category, :priority, :rvs

    def self.create_from_message(component, message)
      options = {
        timestamp: RSMP::Clock.parse(message.attribute('aTs')),
        acknowledged: message.attribute('ack') == 'Acknowledged',
        suspended: message.attribute('aS') == 'Suspended',
        active: message.attribute('sS') == 'Active',
        category: message.attribute('cat'),
        priority: message.attribute('pri').to_i,
        rvs: message.attribute('rvs')
      }
      new(component: component, code: message.attribute('aCId'), **options)
    end

    def initialize(component:, code:, **options)
      @component = component
      @component_id = component.c_id
      @code = code
      @suspended = options[:suspended] == true
      @acknowledged = options[:acknowledged] == true
      @active = options[:active] == true
      @timestamp = options[:timestamp]
      @category = options[:category] || 'D'
      @priority = options[:priority] || 2
      @rvs = options[:rvs] || []
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
      change = !@acknowledged
      @acknowledged = true
      update_timestamp if change
      change
    end

    def suspend
      change = !@suspended
      @suspended = true
      update_timestamp if change
      change
    end

    def resume
      change = @suspended
      @suspended = false
      update_timestamp if change
      change
    end

    # according to the rsmp core spec, the only time an alarm changes to unanknowledged,
    # is when it's activated. See:
    # https://rsmp-nordic.org/rsmp_specifications/core/3.2.0/applicability/basic_structure.html#alarm-status
    def activate
      change = !@active
      @active = true
      @acknowledged = false
      update_timestamp if change
      change
    end

    def deactivate
      change = @active
      @active = false
      update_timestamp if change
      change
    end

    def update_timestamp
      @timestamp = @component.now
    end

    def differ_from_message?(message)
      return true if timestamp_differs?(message)
      return true if acknowledgment_differs?(message)
      return true if suspension_differs?(message)
      return true if activity_differs?(message)
      return true if category_differs?(message)
      return true if priority_differs?(message)

      # return true @rvs = message.attribute('rvs')
      false
    end

    def clear_timestamp
      @timestamp = nil
    end

    def older_message?(message)
      return false if @timestamp.nil?

      RSMP::Clock.parse(message.attribute('aTs')) < @timestamp
    end

    # update from rsmp message
    # component id, alarm code and specialization are not updated
    def update_from_message(message)
      unless differ_from_message? message
        raise RepeatedAlarmError,
              "no changes from previous alarm #{message.m_id_short}"
      end
      raise TimestampError, "timestamp is earlier than previous alarm #{message.m_id_short}" if older_message? message
    ensure
      @timestamp = RSMP::Clock.parse message.attribute('aTs')
      @acknowledged = message.attribute('ack') == 'True'
      @suspended = message.attribute('sS') == 'True'
      @active = message.attribute('aS') == 'True'
      @category = message.attribute('cat')
      @priority = message.attribute('pri').to_i
      @rvs = message.attribute('rvs')
    end

    private

    def timestamp_differs?(message)
      RSMP::Clock.to_s(@timestamp) != message.attribute('aTs')
    end

    def acknowledgment_differs?(message)
      return false unless message.attribute('ack')

      @acknowledged != (message.attribute('ack').downcase == 'acknowledged')
    end

    def suspension_differs?(message)
      return false unless message.attribute('sS')

      @suspended != (message.attribute('sS').downcase == 'suspended')
    end

    def activity_differs?(message)
      return false unless message.attribute('aS')

      @active != (message.attribute('aS').downcase == 'active')
    end

    def category_differs?(message)
      return false unless message.attribute('cat')

      @category != message.attribute('cat')
    end

    def priority_differs?(message)
      return false unless message.attribute('pri')

      @priority != message.attribute('pri').to_i
    end
  end
end
