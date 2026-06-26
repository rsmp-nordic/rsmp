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

        def command_catalogue_item(command_code)
          accepted_sxls.each do |sxl|
            version = RSMP::Schema.sanitize_version(sxl['version'].to_s)
            catalogue = RSMP::Schema.sxl_catalogue(sxl['name'], version, :commands)
            prefix = RSMP::Schema.sxl_prefix(sxl['name'], version, lenient: true)
            unprefixed = prefix && command_code.start_with?(prefix) ? command_code[prefix.length..] : command_code
            item = catalogue[command_code] || catalogue[command_code.to_sym] ||
                   catalogue[unprefixed] || catalogue[unprefixed.to_sym]
            return item if item
          end
          nil
        end

        def required_command_argument_names(command_code)
          item = command_catalogue_item command_code
          return [] unless item

          RSMP::Schema.argument_names(item['required'])
        end

        def check_required_command_arguments(message)
          return unless core_3_3?

          command_codes(message).each do |command_code|
            provided = message.attributes['arg'].select { |item| item['cCI'] == command_code }.map { |item| item['n'] }
            missing = required_command_argument_names(command_code) - provided
            next if missing.empty?

            raise MissingAttribute, "Missing required command argument(s) #{missing.join(', ')} for #{command_code}"
          end
        end

        def mark_command_unknown(rvs, command_code)
          rvs.each do |item|
            next unless item['cCI'] == command_code

            item['age'] = 'unknown'
            item['v'] = nil
          end
        end

        def execute_commands(message, component_id, rvs)
          component = @site.find_component component_id
          commands = simplify_command_requests message.attributes['arg']
          commands.each_pair do |command_code, arg|
            begin
              component.handle_command command_code, arg
            rescue UnknownCommand => e
              log e.to_s, message: message, level: :warning
              mark_command_unknown rvs, command_code
            end
          end
          log "Received #{message.type}", message: message, level: :log
        rescue UnknownComponent
          log "Received #{message.type} with unknown component id '#{component_id}' and cannot infer type",
              message: message, level: :warning
          rvs.map { |item| item['age'] = 'undefined' }
        end

        def process_command_request(message)
          return reject_multiple_command_codes(message) if core_3_3? && multiple_command_codes?(message)

          check_required_command_arguments message
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
