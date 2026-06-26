module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Status request and subscription handling
      module Status
        include StatusUpdates

        def rsmpify_value(value, quality)
          if %w[undefined unknown].include?(quality.to_s)
            nil
          else
            value
          end
        end

        def fetch_status_values(component, args)
          args.map do |arg|
            fetch_status_value component, arg
          end
        end

        def fetch_status_value(component, arg)
          value, quality = component.get_status arg['sCI'], arg['n'], { sxl_version: sxl_version }
          { 's' => rsmpify_value(value, quality), 'q' => quality.to_s }.merge arg
        rescue UnknownStatus => e
          log e.to_s, level: :warning
          { 's' => nil, 'q' => 'unknown' }.merge arg
        end

        def build_undefined_statuses(args)
          args.map { |arg| arg.dup.merge('q' => 'undefined', 's' => nil) }
        end

        def process_status_request(message, options = {})
          component_id = message.attributes['cId']
          args = message.attributes['sS']

          begin
            component = @site.find_component component_id
            ss = fetch_status_values(component, args)
            log "Received #{message.type}", message: message, level: :log
          rescue UnknownComponent
            log "Received #{message.type} with unknown component id '#{component_id}' and cannot infer type",
                message: message, level: :warning
            ss = build_undefined_statuses(args)
          end

          response = StatusResponse.new({
                                          'cId' => component_id,
                                          'sTs' => clock.to_s,
                                          'sS' => ss,
                                          'mId' => options[:m_id]
                                        })

          apply_nts_message_attributes response
          acknowledge message
          send_message response
        end

        def add_status_subscription(component_id, subs, update_list, arg, now)
          sci = arg['sCI']
          name = arg['n']
          subcription = { interval: arg['uRt'].to_i, last_sent_at: now }
          subs[sci] ||= {}
          subs[sci][name] = subcription
          update_list[component_id][sci] ||= []
          update_list[component_id][sci] << name
        end

        def process_status_subcribe(message)
          log "Received #{message.type}", message: message, level: :log

          update_list = {}
          component_id = message.attributes['cId']
          @status_subscriptions[component_id] ||= {}
          update_list[component_id] ||= {}
          now = Time.now
          subs = @status_subscriptions[component_id]

          message.attributes['sS'].each do |arg|
            add_status_subscription(component_id, subs, update_list, arg, now)
          end
          acknowledge message
          send_status_updates update_list
        end

        def get_status_subscribe_interval(component_id, sci, name)
          @status_subscriptions.dig component_id, sci, name
        end

        def remove_status_subscription(subs, arg)
          sci = arg['sCI']
          return unless subs[sci]

          subs[sci].delete arg['n']
          subs.delete(sci) if subs[sci].empty?
        end

        def process_status_unsubcribe(message)
          log "Received #{message.type}", message: message, level: :log
          component = message.attributes['cId']

          subs = @status_subscriptions[component]
          if subs
            message.attributes['sS'].each { |arg| remove_status_subscription(subs, arg) }
            @status_subscriptions.delete(component) if subs.empty?
          end
          acknowledge message
        end

        def prune_unbuffered_status_subscriptions
          @status_subscriptions.each_key.to_a.each do |component_id|
            by_code = @status_subscriptions[component_id]
            by_code.each_key.to_a.each do |code|
              by_name = by_code[code]
              by_name.delete_if do |name, _subscription|
                status = { 'sCI' => code, 'n' => name }
                !status_buffer_selector?(component_id, status)
              end
              by_code.delete(code) if by_name.empty?
            end
            @status_subscriptions.delete(component_id) if by_code.empty?
          end
        end
      end
    end
  end
end
