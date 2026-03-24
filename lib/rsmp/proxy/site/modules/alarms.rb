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
          send_message message, validate: options[:validate]
          message
        end

        # Send an AlarmSuspend message and optionally collect the confirming response.
        # When collect: true, returns [message, response]; when collect: false, returns message.
        def suspend_alarm(task, c_id:, a_c_id:, collect: false)
          message = RSMP::AlarmSuspend.new(
            'mId' => RSMP::Message.make_m_id,
            'cId' => c_id,
            'aCId' => a_c_id
          )
          if collect
            collect_task = task.async do
              RSMP::AlarmCollector.new(self,
                                       m_id: message.m_id,
                                       num: 1,
                                       matcher: {
                                         'cId' => c_id,
                                         'aCI' => a_c_id,
                                         'aSp' => 'Suspend',
                                         'sS' => /^Suspended/i
                                       },
                                       timeout: node.supervisor_settings.dig('default', 'timeouts', 'alarm')).collect!
            end
            send_message message
            [message, collect_task.wait.first]
          else
            send_message message
            message
          end
        end

        # Send an AlarmResume message and optionally collect the confirming response.
        # When collect: true, returns [message, response]; when collect: false, returns message.
        def resume_alarm(task, c_id:, a_c_id:, collect: false)
          message = RSMP::AlarmResume.new(
            'mId' => RSMP::Message.make_m_id,
            'cId' => c_id,
            'aCId' => a_c_id
          )
          if collect
            collect_task = task.async do
              RSMP::AlarmCollector.new(self,
                                       m_id: message.m_id,
                                       num: 1,
                                       matcher: {
                                         'cId' => c_id,
                                         'aCI' => a_c_id,
                                         'aSp' => 'Suspend',
                                         'sS' => /^notSuspended/i
                                       },
                                       timeout: node.supervisor_settings.dig('default', 'timeouts', 'alarm')).collect!
            end
            send_message message
            [message, collect_task.wait.first]
          else
            send_message message
            message
          end
        end
      end
    end
  end
end
