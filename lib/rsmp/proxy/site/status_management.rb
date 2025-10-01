module RSMP
  module SiteProxyExtensions
    module StatusManagement
      def request_status(component, status_list, options = {})
        validate_ready 'request status'
        m_id = ensure_message_id(options)
        request_list = status_list.map { |item| item.slice('sCI', 'n') }

        message = RSMP::StatusRequest.new({
                                            'cId' => component,
                                            'sS' => request_list,
                                            'mId' => m_id
                                          })
        assign_nts_message_attributes message
        send_and_optionally_collect message, options do |collect_options|
          build_status_collector(status_list, collect_options, m_id)
        end
      end

      def process_status_response(message)
        component = find_component message.attribute('cId')
        component.store_status message
        log "Received #{message.type}", message: message, level: :log
        acknowledge message
      end

      def subscribe_to_status(component_id, status_list, options = {})
        validate_ready 'subscribe to status'
        m_id = ensure_message_id(options)
        subscribe_list = build_subscribe_list(status_list)
        update_subscription_cache(component_id, subscribe_list)
        find_component component_id

        message = build_status_subscribe_message(component_id, subscribe_list, m_id)
        assign_nts_message_attributes message

        send_and_optionally_collect message, options do |collect_options|
          build_status_collector(status_list, collect_options, m_id)
        end
      end

      def unsubscribe_to_status(component_id, status_list, options = {})
        validate_ready 'unsubscribe to status'

        remove_subscription_entries(component_id, status_list)

        message = build_status_unsubscribe_message(component_id, status_list)
        assign_nts_message_attributes message
        send_message message, validate: options[:validate]
        message
      end

      def process_status_update(message)
        component = find_component message.attribute('cId')
        component.check_repeat_values message, @status_subscriptions
        component.store_status message
        log "Received #{message.type}", message: message, level: :log
        acknowledge message
      end
    end
  end
end
