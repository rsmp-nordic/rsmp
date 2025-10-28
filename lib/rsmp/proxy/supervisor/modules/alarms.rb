module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Alarm handling
      module Alarms
        def send_alarm(_component, alarm, options = {})
          send_and_optionally_collect alarm, options do |collect_options|
            Collector.new self, collect_options.merge(task: @task, type: 'MessageAck')
          end
        end

        def send_active_alarms
          @site.components.each_pair do |_c_id, component|
            component.alarms.each_pair do |_alarm_code, alarm_state|
              if alarm_state.active
                alarm = AlarmIssue.new(alarm_state.to_hash.merge('aSp' => 'Issue'))
                send_message alarm
              end
            end
          end
        end

        def process_alarm(message)
          case message
          when AlarmAcknowledge
            handle_alarm_acknowledge message
          when AlarmSuspend
            handle_alarm_suspend message
          when AlarmResume
            handle_alarm_resume message
          when AlarmRequest
            handle_alarm_request message
          else
            dont_acknowledge message, 'Invalid alarm message type'
          end
        end

        def handle_alarm_acknowledge(message)
          component_id = message.attributes['cId']
          component = @site.find_component component_id
          alarm_code = message.attribute('aCId')
          log "Received #{message.type} #{alarm_code} acknowledgement", message: message, level: :log
          acknowledge message
          component.acknowledge_alarm alarm_code
        end

        def handle_alarm_suspend(message)
          component_id = message.attributes['cId']
          component = @site.find_component component_id
          alarm_code = message.attribute('aCId')
          log "Received #{message.type} #{alarm_code} suspend", message: message, level: :log
          acknowledge message
          component.suspend_alarm alarm_code
        end

        def handle_alarm_resume(message)
          component_id = message.attributes['cId']
          component = @site.find_component component_id
          alarm_code = message.attribute('aCId')
          log "Received #{message.type} #{alarm_code} resume", message: message, level: :log
          acknowledge message
          component.resume_alarm alarm_code
        end

        def handle_alarm_request(message)
          log "Received #{message.type}", message: message, level: :log
          acknowledge message
          send_active_alarms
        end
      end
    end
  end
end
