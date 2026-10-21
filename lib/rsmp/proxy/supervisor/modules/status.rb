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
          send_generated_message response
        end

        def add_status_subscription(component_id, subs, update_list, arg, now)
          sci = arg['sCI']
          name = arg['n']
          subcription = { interval: arg['uRt'].to_f, last_sent_at: now }
          subcription[:on_change] = arg['sOc'] if core_3_3_0_or_newer?
          subs[sci] ||= {}
          subs[sci][name] = subcription
          update_list[component_id][sci] ||= []
          update_list[component_id][sci] << name
        end

        def process_status_subcribe(message)
          log "Received #{message.type}", message: message, level: :log

          return process_core_3_3_subscription(message) if core_3_3_0_or_newer?

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

        def process_core_3_3_subscription(message)
          validate_core_3_3_subscription!(message)
          id = message.attributes['cId']
          args = message.attributes['sS']
          component = @site.find_component(id, build: false)
          values = component ? fetch_status_values(component, args) : build_undefined_statuses(args)
          subs = (@status_subscriptions[id] ||= {})
          update_core_3_3_subscriptions(id, args, values, subs)
          @status_subscriptions.delete(id) if subs.empty?
          acknowledge message
          update = core_3_3_subscription_update(id, values)
          send_generated_message update
          store_last_sent_status update
        end

        def core_3_3_subscription_update(id, values)
          values = values.map { |value| value.except('uRt', 'sOc') }
          StatusUpdate.new('cId' => id, 'sTs' => clock.to_s, 'sS' => values)
        end

        def update_core_3_3_subscriptions(id, args, values, subs)
          updates = { id => {} }
          values.each_with_index do |value, index|
            arg = args[index]
            if %w[unknown undefined].include?(value['q'])
              remove_status_subscription(subs, arg)
            else
              add_status_subscription(id, subs, updates, arg, Time.now)
            end
          end
        end

        def validate_core_3_3_subscription!(message)
          invalid = message.attributes['sS'].any? do |arg|
            interval = arg['uRt'].to_f
            interval.negative? || (interval.zero? && !arg['sOc'])
          end
          return unless invalid

          raise MessageRejected, 'Subscription interval must be nonnegative and enable interval or sendOnChange'
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
