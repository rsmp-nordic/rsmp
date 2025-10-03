# frozen_string_literal: true

module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Status request and subscription handling
      module Status
        def rsmpify_value(value, quality)
          if value.is_a?(Array) || value.is_a?(Set)
            value
          elsif %w[undefined unknown].include?(quality.to_s)
            nil
          else
            value.to_s
          end
        end

        def fetch_status_values(component, args)
          args.map do |arg|
            value, quality = component.get_status arg['sCI'], arg['n'], { sxl_version: sxl_version }
            { 's' => rsmpify_value(value, quality), 'q' => quality.to_s }.merge arg
          end
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

        def process_status_subcribe(message)
          log "Received #{message.type}", message: message, level: :log

          update_list = {}
          component_id = message.attributes['cId']
          @status_subscriptions[component_id] ||= {}
          update_list[component_id] ||= {}
          now = Time.now
          subs = @status_subscriptions[component_id]

          message.attributes['sS'].each do |arg|
            sci = arg['sCI']
            subcription = { interval: arg['uRt'].to_i, last_sent_at: now }
            subs[sci] ||= {}
            subs[sci][arg['n']] = subcription
            update_list[component_id][sci] ||= []
            update_list[component_id][sci] << arg['n']
          end
          acknowledge message
          send_status_updates update_list
        end

        def get_status_subscribe_interval(component_id, sci, name)
          @status_subscriptions.dig component_id, sci, name
        end

        def process_status_unsubcribe(message)
          log "Received #{message.type}", message: message, level: :log
          component = message.attributes['cId']

          subs = @status_subscriptions[component]
          if subs
            message.attributes['sS'].each do |arg|
              sci = arg['sCI']
              if subs[sci]
                subs[sci].delete arg['n']
                subs.delete(sci) if subs[sci].empty?
              end
            end
            @status_subscriptions.delete(component) if subs.empty?
          end
          acknowledge message
        end

        def fetch_last_sent_status(component, code, name)
          @last_status_sent&.dig component, code, name
        end

        def store_last_sent_status(message)
          component_id = message.attribute('cId')
          @last_status_sent ||= {}
          @last_status_sent[component_id] ||= {}
          message.attribute('sS').each do |item|
            sci = item['sCI']
            n = item['n']
            s = item['s']
            @last_status_sent[component_id][sci] ||= {}
            @last_status_sent[component_id][sci][n] = s
          end
        end

        def check_on_change_update(subscription, component, code, name)
          return [nil, false] unless subscription[:interval].zero?

          current = nil
          if component
            current, quality = *(component.get_status code, name)
            current = rsmpify_value(current, quality)
          end
          last_sent = fetch_last_sent_status component.id, code, name
          [current, current != last_sent]
        end

        def interval_update_due?(subscription, now)
          return true if subscription[:last_sent_at].nil?

          (now - subscription[:last_sent_at]) >= subscription[:interval]
        end

        def check_status_subscription(subscription, component, code, name, now)
          current, should_send = check_on_change_update(subscription, component, code, name)
          should_send ||= interval_update_due?(subscription, now)
          return [nil, false] unless should_send

          subscription[:last_sent_at] = now
          [current, true]
        end

        def status_update_timer(now)
          update_list = {}

          @status_subscriptions.each_pair do |component_id, by_code|
            component = @site.find_component component_id
            by_code.each_pair do |code, by_name|
              by_name.each_pair do |name, subscription|
                current, should_send = check_status_subscription(subscription, component, code, name, now)
                next unless should_send

                update_list[component_id] ||= {}
                update_list[component_id][code] ||= {}
                update_list[component_id][code][name] = current
              end
            end
          end
          send_status_updates update_list
        end

        def build_status_list(component, by_code)
          ss = []
          by_code.each_pair do |code, names|
            names.map do |status_name, value|
              if value
                quality = 'recent'
              else
                value, quality = component.get_status code, status_name
              end
              ss << { 'sCI' => code,
                      'n' => status_name,
                      's' => rsmpify_value(value, quality),
                      'q' => quality }
            end
          end
          ss
        end

        def send_status_updates(update_list)
          now = clock.to_s
          update_list.each_pair do |component_id, by_code|
            component = @site.find_component component_id
            ss = build_status_list(component, by_code)
            update = StatusUpdate.new({
                                        'cId' => component_id,
                                        'sTs' => now,
                                        'sS' => ss
                                      })
            apply_nts_message_attributes update
            send_message update
            store_last_sent_status update
            component.status_updates_sent
          end
        end
      end
    end
  end
end
