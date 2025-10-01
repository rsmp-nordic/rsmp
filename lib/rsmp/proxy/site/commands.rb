module RSMP
  module SiteProxyExtensions
    module Commands
      def process_command_response(message)
        log "Received #{message.type}", message: message, level: :log
        acknowledge message
      end

      def send_command(component, command_list, options = {})
        validate_ready 'send command'
        m_id = ensure_message_id(options)
        message = RSMP::CommandRequest.new({
                                             'cId' => component,
                                             'arg' => command_list,
                                             'mId' => m_id
                                           })
        assign_nts_message_attributes message
        send_and_optionally_collect message, options do |collect_options|
          CommandResponseCollector.new(
            self,
            command_list,
            collect_options.merge(task: @task, m_id: m_id)
          )
        end
      end
    end
  end
end
