module RSMP
  module SupervisorProxyExtensions
    module Messages
      def process_message(message)
        case message
        when StatusResponse, StatusUpdate, AggregatedStatus, AlarmIssue
          will_not_handle message
        when AggregatedStatusRequest
          process_aggregated_status_request message
        when CommandRequest
          process_command_request message
        when CommandResponse
          process_command_response message
        when StatusRequest
          process_status_request message
        when StatusSubscribe
          process_status_subcribe message
        when StatusUnsubscribe
          process_status_unsubcribe message
        when Alarm, AlarmAcknowledged, AlarmSuspend, AlarmResume, AlarmRequest
          process_alarm message
        else
          super
        end
      rescue UnknownComponent, UnknownCommand, UnknownStatus,
             MessageRejected, MissingAttribute => e
        dont_acknowledge message, '', e.to_s
      end

      def acknowledged_first_ingoing(message)
        handshake_complete if message.type == 'Watchdog'
      end
    end
  end
end
