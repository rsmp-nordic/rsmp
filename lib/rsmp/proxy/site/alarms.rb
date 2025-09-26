module RSMP
  module SiteProxyExtensions
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
    end
  end
end
