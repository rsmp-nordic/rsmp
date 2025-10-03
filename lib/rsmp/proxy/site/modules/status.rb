# frozen_string_literal: true

module RSMP
  class SiteProxy < Proxy
    module Modules
      # Handles status requests, responses, subscriptions and updates
      module Status
        def request_status(component, status_list, options = {})
          validate_ready 'request status'
          m_id = options[:m_id] || RSMP::Message.make_m_id

          # additional items can be used when verifying the response,
          # but must be removed from the request
          request_list = status_list.map { |item| item.slice('sCI', 'n') }

          message = RSMP::StatusRequest.new({
                                              'cId' => component,
                                              'sS' => request_list,
                                              'mId' => m_id
                                            })
          apply_nts_message_attributes message
          send_and_optionally_collect message, options do |collect_options|
            StatusCollector.new(
              self,
              status_list,
              collect_options.merge(task: @task, m_id: m_id)
            )
          end
        end

        def process_status_response(message)
          component = find_component message.attribute('cId')
          component.store_status message
          log "Received #{message.type}", message: message, level: :log
          acknowledge message
        end

        def ensure_subscription_path(component_id, sci, n)
          @status_subscriptions[component_id] ||= {}
          @status_subscriptions[component_id][sci] ||= {}
          @status_subscriptions[component_id][sci][n] ||= {}
        end

        def update_subscription(component_id, subscribe_list)
          subscribe_list.each do |item|
            sci = item['sCI']
            n = item['n']
            sub = ensure_subscription_path(component_id, sci, n)
            sub['uRt'] = item['uRt']
            sub['sOc'] = item['sOc']
          end
        end

        def subscribe_to_status(component_id, status_list, options = {})
          validate_ready 'subscribe to status'
          m_id = options[:m_id] || RSMP::Message.make_m_id
          subscribe_list = status_list.map { |item| item.slice('sCI', 'n', 'uRt', 'sOc') }

          update_subscription(component_id, subscribe_list)
          find_component component_id

          message = RSMP::StatusSubscribe.new({
                                                'cId' => component_id,
                                                'sS' => subscribe_list,
                                                'mId' => m_id
                                              })
          apply_nts_message_attributes message

          send_and_optionally_collect message, options do |collect_options|
            StatusCollector.new(
              self,
              status_list,
              collect_options.merge(task: @task, m_id: m_id)
            )
          end
        end

        def unsubscribe_to_status(component_id, status_list, options = {})
          validate_ready 'unsubscribe to status'

          # update our subcription list
          status_list.each do |item|
            sci = item['sCI']
            n = item['n']
            next unless @status_subscriptions.dig(component_id, sci, n)

            @status_subscriptions[component_id][sci].delete n
            @status_subscriptions[component_id].delete(sci) if @status_subscriptions[component_id][sci].empty?
            @status_subscriptions.delete(component_id) if @status_subscriptions[component_id].empty?
          end

          message = RSMP::StatusUnsubscribe.new({
                                                  'cId' => component_id,
                                                  'sS' => status_list
                                                })
          apply_nts_message_attributes message
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
end
