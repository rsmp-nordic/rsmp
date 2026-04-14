module RSMP
  class SiteProxy < Proxy
    module Modules
      # Handles command requests and responses
      module Commands
        def send_command(component, command_list, within: nil, m_id: nil, validate: true)
          validate_ready 'send command'
          m_id ||= RSMP::Message.make_m_id
          message = RSMP::CommandRequest.new({
                                               'cId' => component,
                                               'arg' => command_list,
                                               'mId' => m_id
                                             })
          apply_nts_message_attributes message
          if within
            collector = CommandResponseCollector.new(self, command_list, timeout: within, m_id: m_id)
            send_message_and_collect message, collector, validate: validate
          else
            send_message message, validate: validate
            { sent: message }
          end
        end

        def process_command_response(message)
          log "Received #{message.type}", message: message, level: :log
          acknowledge message
        end
      end
    end
  end
end
