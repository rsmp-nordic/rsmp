module RSMP
  module SupervisorProxyExtensions
    module SubscriptionManagement
      def process_status_subcribe(message)
        log "Received #{message.type}", message: message, level: :log

        component_id = message.attributes['cId']
        update_list = prepare_subscription(component_id, message)

        acknowledge message
        send_status_updates update_list
      end

      def process_status_unsubcribe(message)
        log "Received #{message.type}", message: message, level: :log

        component_id = message.attributes['cId']
        subs = @status_subscriptions[component_id]
        if subs
          message.attributes['sS'].each do |arg|
            remove_subscription(subs, arg)
          end
          @status_subscriptions.delete(component_id) if subs.empty?
        end

        acknowledge message
      end

      def get_status_subscribe_interval(component_id, sci, name)
        @status_subscriptions.dig component_id, sci, name
      end

      private

      def prepare_subscription(component_id, message)
        now = Time.now
        subs = (@status_subscriptions[component_id] ||= {})
        update_list = { component_id => {} }

        message.attributes['sS'].each do |arg|
          register_subscription(subs, update_list[component_id], arg, now)
        end

        update_list
      end

      def register_subscription(subs, updates, arg, now)
        sci = arg['sCI']
        subs[sci] ||= {}
        subs[sci][arg['n']] = { interval: arg['uRt'].to_i, last_sent_at: now }
        (updates[sci] ||= []) << arg['n']
      end

      def remove_subscription(subs, arg)
        sci = arg['sCI']
        return unless subs[sci]

        subs[sci].delete arg['n']
        subs.delete(sci) if subs[sci].empty?
      end
    end

    module StatusHistory
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
    end

    module StatusUpdates
      include StatusHistory

      def status_update_timer(now)
        send_status_updates build_update_list(now)
      end

      def send_status_updates(update_list)
        now = clock.to_s
        update_list.each_pair do |component_id, by_code|
          component = @site.find_component component_id
          ss = build_status_updates(component, by_code)
          update = StatusUpdate.new('cId' => component_id, 'sTs' => now, 'sS' => ss)
          assign_nts_message_attributes update
          send_message update
          store_last_sent_status update
          component.status_updates_sent
        end
      end

      private

      def build_update_list(now)
        @status_subscriptions.each_with_object({}) do |(component_id, by_code), list|
          component = @site.find_component component_id
          by_code.each_pair do |code, by_name|
            by_name.each_pair do |name, subscription|
              context = {
                subscription: subscription,
                component_id: component_id,
                component: component,
                code: code,
                name: name,
                now: now
              }
              record_update(list, context)
            end
          end
        end
      end

      def record_update(list, context)
        send_update, current = determine_update(context)
        return unless send_update

        context[:subscription][:last_sent_at] = context[:now]
        component_id = context[:component_id]
        code = context[:code]
        list[component_id] ||= {}
        list[component_id][code] ||= {}
        list[component_id][code][context[:name]] = current
      end

      def determine_update(context)
        subscription = context[:subscription]

        if subscription[:interval].zero?
          current = fetch_current_status(context[:component], context[:code], context[:name])
          last_sent = fetch_last_sent_status context[:component_id], context[:code], context[:name]
          return [true, current] if current != last_sent
        else
          last_sent_at = subscription[:last_sent_at]
          return [true, nil] if last_sent_at.nil? || (context[:now] - last_sent_at) >= subscription[:interval]
        end
        [false, nil]
      end

      def fetch_current_status(component, code, name)
        return unless component

        value, quality = component.get_status code, name
        rsmpify_value(value, quality)
      end

      def build_status_updates(component, by_code)
        by_code.each_with_object([]) do |(code, names), ss|
          iterate_status_names(names) do |status_name, value|
            ss << build_status_update(component, code, status_name, value)
          end
        end
      end

      def build_status_update(component, code, status_name, value)
        if value
          quality = 'recent'
        else
          value, quality = component.get_status code, status_name
        end
        { 'sCI' => code,
          'n' => status_name,
          's' => rsmpify_value(value, quality),
          'q' => quality }
      end

      def iterate_status_names(names, &block)
        if names.respond_to?(:each_pair)
          names.each_pair(&block)
        else
          Array(names).each { |status_name| block.call(status_name, nil) }
        end
      end
    end

    module Subscriptions
      include SubscriptionManagement
      include StatusUpdates
    end
  end
end
