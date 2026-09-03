module RSMP
  class SiteProxy < Proxy
    module Modules
      # Handles command requests and responses
      module Commands
        # Build and send a CommandRequest. Returns Result<CommandRequest>.
        def send_command(command_list, component: nil, validate: true)
          readiness = validate_ready 'send command'
          return readiness if readiness.failure?

          component ||= main.c_id
          m_id = RSMP::Message.make_m_id
          message = RSMP::CommandRequest.new({
                                               'cId' => component,
                                               'arg' => command_list,
                                               'mId' => m_id
                                             })
          apply_nts_message_attributes message
          send_message(message, validate: validate).map(&:message)
        end

        def send_command!(...)
          send_command(...).value!
        end

        # Build, send a CommandRequest and collect its responses. Returns Result<Exchange>.
        def send_command_and_collect(command_list, within:, component: nil, validate: true)
          readiness = validate_ready 'send command'
          return readiness if readiness.failure?

          component ||= main.c_id
          m_id = RSMP::Message.make_m_id
          collector_list = command_collector_list(command_list)
          message = RSMP::CommandRequest.new({
                                               'cId' => component,
                                               'arg' => command_list,
                                               'mId' => m_id
                                             })
          apply_nts_message_attributes message
          collector = CommandResponseCollector.new(self, collector_list, timeout: within, initiator: message)
          send_message_and_collect(message, collector, validate: validate)
        end

        def send_command_and_collect!(...)
          send_command_and_collect(...).value!
        end

        def command_collector_list(command_list)
          list = JSON.parse(JSON.generate(command_list))
          resolved = RSMP::Schema.resolve_sxl({ 'type' => 'CommandRequest', 'arg' => list }, schemas: schemas)
          return list unless resolved

          type, version = resolved
          list.each do |item|
            next unless item.key?('v')

            descriptor = RSMP::Schema.sxl_argument_descriptor(type, version, :commands, item['cCI'], item['n'])
            next unless descriptor

            encoded = RSMP::Message.encode_sxl_value(item['v'], descriptor)
            item['v'] = RSMP::Message.decode_sxl_value(encoded, descriptor)
          end
          list
        rescue RSMP::Schema::Error
          list
        end

        def process_command_response(message)
          return reject_multiple_command_codes(message) if core_3_3? && multiple_command_codes?(message)

          log "Received #{message.type}", message: message, level: :log
          acknowledge message
        end
      end
    end
  end
end
