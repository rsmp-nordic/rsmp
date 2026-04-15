module RSMP
  class SiteProxy < Proxy
    module Modules
      # Handles command requests and responses
      module Commands
        # Build and send a CommandRequest. Returns the CommandRequest message.
        def send_command(command_list, component: nil, validate: true)
          validate_ready 'send command'
          component ||= main.c_id
          m_id = RSMP::Message.make_m_id
          message = RSMP::CommandRequest.new({
                                               'cId' => component,
                                               'arg' => command_list,
                                               'mId' => m_id
                                             })
          apply_nts_message_attributes message
          send_message message, validate: validate
          message
        end

        # Build, send a CommandRequest and collect the CommandResponse. Returns the collector.
        # Raises on NotAck or timeout if ok! is called on the result.
        def send_command_and_collect(command_list, within:, component: nil, validate: true)
          validate_ready 'send command'
          component ||= main.c_id
          m_id = RSMP::Message.make_m_id
          message = RSMP::CommandRequest.new({
                                               'cId' => component,
                                               'arg' => command_list,
                                               'mId' => m_id
                                             })
          apply_nts_message_attributes message
          collector = CommandResponseCollector.new(self, command_list, timeout: within, initiator: message)
          send_message_and_collect(message, collector, validate: validate)[:collector]
        end

        def process_command_response(message)
          log "Received #{message.type}", message: message, level: :log
          acknowledge message
        end
      end
    end
  end
end
