# frozen_string_literal: true

module RSMP
  class SiteProxy < Proxy
    module Modules
      # Handles command requests and responses
      module CommandHandling
        def send_command(component, command_list, options = {})
          validate_ready 'send command'
          m_id = options[:m_id] || RSMP::Message.make_m_id
          message = RSMP::CommandRequest.new({
                                               'cId' => component,
                                               'arg' => command_list,
                                               'mId' => m_id
                                             })
          apply_nts_message_attributes message
          send_and_optionally_collect message, options do |collect_options|
            CommandResponseCollector.new(
              self,
              command_list,
              collect_options.merge(task: @task, m_id: m_id)
            )
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
