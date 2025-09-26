module RSMP
  module SiteProxyExtensions
    module StatusHelpers
      private

      def build_status_collector(status_list, collect_options, m_id)
        StatusCollector.new(
          self,
          status_list,
          collect_options.merge(task: @task, m_id: m_id)
        )
      end

      def build_subscribe_list(status_list)
        status_list.map { |item| item.slice('sCI', 'n', 'uRt', 'sOc') }
      end

      def update_subscription_cache(component_id, subscribe_list)
        @status_subscriptions[component_id] ||= {}
        subscribe_list.each do |item|
          cache_subscription_item(component_id, item)
        end
      end

      def cache_subscription_item(component_id, item)
        sci = item['sCI']
        n = item['n']
        urt = item['uRt']
        soc = item['sOc']
        @status_subscriptions[component_id][sci] ||= {}
        @status_subscriptions[component_id][sci][n] ||= {}
        @status_subscriptions[component_id][sci][n]['uRt'] = urt
        @status_subscriptions[component_id][sci][n]['sOc'] = soc
      end

      def remove_subscription_entries(component_id, status_list)
        status_list.each do |item|
          remove_subscription_entry(component_id, item)
        end
      end

      def remove_subscription_entry(component_id, item)
        sci = item['sCI']
        n = item['n']
        return unless @status_subscriptions.dig(component_id, sci, n)

        @status_subscriptions[component_id][sci].delete n
        cleanup_subscription_tree(component_id, sci)
      end

      def cleanup_subscription_tree(component_id, sci)
        @status_subscriptions[component_id].delete(sci) if @status_subscriptions[component_id][sci].empty?
        return unless @status_subscriptions[component_id]
        return unless @status_subscriptions[component_id].empty?

        @status_subscriptions.delete(component_id)
      end

      def build_status_subscribe_message(component_id, subscribe_list, m_id)
        RSMP::StatusSubscribe.new({
                                    'cId' => component_id,
                                    'sS' => subscribe_list,
                                    'mId' => m_id
                                  })
      end

      def build_status_unsubscribe_message(component_id, status_list)
        RSMP::StatusUnsubscribe.new({
                                      'cId' => component_id,
                                      'sS' => status_list
                                    })
      end
    end
  end
end
