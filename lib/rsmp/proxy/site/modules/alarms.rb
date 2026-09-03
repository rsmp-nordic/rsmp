module RSMP
  class SiteProxy < Proxy
    module Modules
      # Handles alarm messages
      module Alarms
        def process_alarm(message)
          component = find_component message.attribute('cId')
          status = %w[ack aS sS].map { |key| message.attribute(key) }.join(',')
          component.handle_alarm message
          alarm_code = message.attribute('aCId')
          asp = message.attribute('aSp')
          log "Received #{message.type}, #{alarm_code} #{asp} [#{status}]", message: message, level: :log
          acknowledge message
        end

        def send_alarm_acknowledgement(component, alarm_code, options = {})
          message = RSMP::AlarmAcknowledged.new({
                                                  'cId' => component,
                                                  'aCId' => alarm_code
                                                })
          send_message(message, validate: options[:validate]).map(&:message)
        end

        def send_alarm_acknowledgement!(...)
          send_alarm_acknowledgement(...).value!
        end

        # Send an AlarmSuspend message and optionally collect the confirming response.
        # Returns Result<Exchange> when collecting and Result<AlarmSuspend> otherwise.
        def suspend_alarm(c_id:, a_c_id:, collect: false)
          message = RSMP::AlarmSuspend.new(
            'mId' => RSMP::Message.make_m_id,
            'cId' => c_id,
            'aCId' => a_c_id
          )
          if collect
            collector = RSMP::AlarmCollector.new(
              self,
              m_id: message.m_id,
              num: 1,
              matcher: {
                'cId' => c_id,
                'aCId' => a_c_id,
                'aSp' => 'Suspend',
                'sS' => /^Suspended/i
              },
              timeout: node.supervisor_settings.dig('default', 'timeouts', 'alarm')
            )
            send_message_and_collect(message, collector)
          else
            send_message(message).map(&:message)
          end
        end

        def suspend_alarm!(...)
          suspend_alarm(...).value!
        end

        # Send an AlarmResume message and optionally collect the confirming response.
        # Returns Result<Exchange> when collecting and Result<AlarmResume> otherwise.
        def resume_alarm(c_id:, a_c_id:, collect: false)
          message = RSMP::AlarmResume.new(
            'mId' => RSMP::Message.make_m_id,
            'cId' => c_id,
            'aCId' => a_c_id
          )
          if collect
            collector = RSMP::AlarmCollector.new(
              self,
              m_id: message.m_id,
              num: 1,
              matcher: {
                'cId' => c_id,
                'aCId' => a_c_id,
                'aSp' => 'Suspend',
                'sS' => /^notSuspended/i
              },
              timeout: node.supervisor_settings.dig('default', 'timeouts', 'alarm')
            )
            send_message_and_collect(message, collector)
          else
            send_message(message).map(&:message)
          end
        end

        def resume_alarm!(...)
          resume_alarm(...).value!
        end
      end
    end
  end
end
