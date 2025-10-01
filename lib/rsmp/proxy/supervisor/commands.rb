module RSMP
  module SupervisorProxyExtensions
    module Commands
      def process_command_request(message)
        component_id = message.attributes['cId']
        rvs = normalize_command_arguments(message)

        begin
          component = @site.find_component component_id
          execute_commands component, message.attributes['arg']
          log "Received #{message.type}", message: message, level: :log
        rescue UnknownComponent
          handle_unknown_command_component message, component_id, rvs
        end

        response = build_command_response(component_id, rvs)
        assign_nts_message_attributes response
        acknowledge message
        send_message response
      end

      def simplify_command_requests(arg)
        arg.each_with_object({}) do |item, sorted|
          sorted[item['cCI']] ||= {}
          sorted[item['cCI']][item['n']] = item['v']
        end
      end

      private

      def normalize_command_arguments(message)
        message.attributes['arg'].map do |item|
          item.dup.merge('age' => 'recent').tap { |copy| copy.delete 'cO' }
        end
      end

      def execute_commands(component, arguments)
        simplify_command_requests(arguments).each_pair do |command_code, arg|
          component.handle_command command_code, arg
        end
      end

      def handle_unknown_command_component(message, component_id, rvs)
        log "Received #{message.type} with unknown component id '#{component_id}' and cannot infer type",
            message: message, level: :warning
        rvs.each { |item| item['age'] = 'undefined' }
      end

      def build_command_response(component_id, rvs)
        CommandResponse.new({
                              'cId' => component_id,
                              'cTS' => clock.to_s,
                              'rvs' => rvs
                            })
      end
    end
  end
end
