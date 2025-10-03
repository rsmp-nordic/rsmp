# frozen_string_literal: true

module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Command request handling
      module Commands
        def simplify_command_requests(arg)
          sorted = {}
          arg.each do |item|
            sorted[item['cCI']] ||= {}
            sorted[item['cCI']][item['n']] = item['v']
          end
          sorted
        end

        def build_command_rvs(args)
          args.map do |item|
            item = item.dup.merge('age' => 'recent')
            item.delete 'cO'
            item
          end
        end

        def execute_commands(message, component_id, rvs)
          component = @site.find_component component_id
          commands = simplify_command_requests message.attributes['arg']
          commands.each_pair do |command_code, arg|
            component.handle_command command_code, arg
          end
          log "Received #{message.type}", message: message, level: :log
        rescue UnknownComponent
          log "Received #{message.type} with unknown component id '#{component_id}' and cannot infer type",
              message: message, level: :warning
          rvs.map { |item| item['age'] = 'undefined' }
        end

        def process_command_request(message)
          component_id = message.attributes['cId']
          rvs = build_command_rvs(message.attributes['arg'])
          execute_commands(message, component_id, rvs)

          response = CommandResponse.new({
                                           'cId' => component_id,
                                           'cTS' => clock.to_s,
                                           'rvs' => rvs
                                         })
          apply_nts_message_attributes response
          acknowledge message
          send_message response
        end
      end
    end
  end
end
