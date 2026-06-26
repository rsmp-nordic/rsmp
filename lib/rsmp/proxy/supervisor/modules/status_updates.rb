module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Periodic and on-change status update handling.
      module StatusUpdates
        PrecomputedStatusValue = Struct.new(:value)

        def fetch_last_sent_status(component, code, name)
          @last_status_sent&.dig component, code, name
        end

        def store_last_sent_status(message)
          component_id = message.attribute('cId')
          @last_status_sent ||= {}
          @last_status_sent[component_id] ||= {}
          message.attribute('sS').each { |item| store_last_sent_status_item(component_id, item) }
        end

        def store_last_sent_status_item(component_id, item)
          @last_status_sent[component_id][item['sCI']] ||= {}
          @last_status_sent[component_id][item['sCI']][item['n']] = item['s']
        end

        def check_on_change_update(subscription, component, code, name)
          return [nil, false] unless subscription[:interval].zero?

          current = current_status_value(component, code, name)
          last_sent = fetch_last_sent_status component.c_id, code, name
          [current, encode_status_value(code, name, current) != last_sent]
        end

        def current_status_value(component, code, name)
          return unless component

          value, quality = *(component.get_status code, name)
          rsmpify_value(value, quality)
        end

        def encode_status_value(code, name, value)
          message = { 'type' => 'StatusUpdate', 'sS' => [{ 'sCI' => code, 'n' => name }] }
          type, version = RSMP::Schema.resolve_sxl(message, schemas: schemas)
          descriptor = RSMP::Schema.sxl_argument_descriptor(type, version, :statuses, code, name)
          descriptor ? RSMP::Message.encode_sxl_value(value, descriptor) : value
        end

        def interval_update_due?(subscription, now)
          return true if subscription[:last_sent_at].nil?

          (now - subscription[:last_sent_at]) >= subscription[:interval]
        end

        def check_status_subscription(subscription, component, code, name, now)
          current, should_send = check_on_change_update(subscription, component, code, name)
          should_send ||= interval_update_due?(subscription, now) if subscription[:interval].positive?
          return [nil, false] unless should_send

          subscription[:last_sent_at] = now
          [current, true]
        end

        def status_update_timer(now)
          send_status_updates status_updates_due(now)
        end

        def status_updates_due(now)
          update_list = {}
          @status_subscriptions.each_pair do |component_id, by_code|
            collect_component_status_updates(update_list, component_id, by_code, now)
          end
          update_list
        end

        def collect_component_status_updates(update_list, component_id, by_code, now)
          component = @site.find_component component_id
          by_code.each_pair do |code, by_name|
            by_name.each_pair do |name, subscription|
              current, should_send = check_status_subscription(subscription, component, code, name, now)
              next unless should_send

              value = precomputed_status_value(subscription, current)
              add_status_update(update_list, component.c_id, code, name, value)
            end
          end
        end

        def add_status_update(update_list, component_id, code, name, value)
          update_list[component_id] ||= {}
          update_list[component_id][code] ||= {}
          update_list[component_id][code][name] = value
        end

        def precomputed_status_value(subscription, current)
          PrecomputedStatusValue.new(current) if subscription[:interval].zero?
        end

        def build_status_list(component, by_code)
          by_code.each_pair.with_object([]) do |(code, names), ss|
            each_status_name(names) do |status_name, value|
              ss << build_status_item(component, code, status_name, value)
            end
          end
        end

        def each_status_name(names, &block)
          if names.respond_to?(:each_pair)
            names.each_pair(&block)
          else
            names.each { |status_name| block.call(status_name, nil) }
          end
        end

        def build_status_item(component, code, status_name, value)
          value, quality = status_item_value(component, code, status_name, value)
          { 'sCI' => code, 'n' => status_name, 's' => rsmpify_value(value, quality), 'q' => quality }
        end

        def status_item_value(component, code, status_name, value)
          return [value.value, 'recent'] if value.is_a?(PrecomputedStatusValue)

          component.get_status code, status_name
        rescue UnknownStatus => e
          log e.to_s, level: :warning
          [nil, 'unknown']
        end

        def send_status_updates(update_list)
          now = clock.to_s
          update_list.each_pair do |component_id, by_code|
            send_component_status_update(component_id, by_code, now)
          end
        end

        def send_component_status_update(component_id, by_code, now)
          component = @site.find_component component_id
          update = StatusUpdate.new({
                                      'cId' => component_id,
                                      'sTs' => now,
                                      'sS' => build_status_list(component, by_code)
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
