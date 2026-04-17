module RSMP
  class SiteProxy < Proxy
    module Modules
      # Handles status requests, responses, subscriptions and updates
      module Status
        # Build and send a StatusRequest. Returns { sent: message }.
        def request_status(status_list, component: nil, m_id: nil, validate: true)
          validate_ready 'request status'
          component ||= main.c_id
          m_id ||= RSMP::Message.make_m_id

          list = RSMP::StatusList.new(status_list)

          # additional items can be used when verifying the response,
          # but must be removed from the request
          request_list = list.map { |item| item.slice('sCI', 'n') }

          message = RSMP::StatusRequest.new({
                                              'cId' => component,
                                              'sS' => request_list,
                                              'mId' => m_id
                                            })
          apply_nts_message_attributes message
          send_message message, validate: validate
          { sent: message }
        end

        # Build, send a StatusRequest and collect the StatusResponse. Returns the collector.
        # Call .ok! on the result to raise on NotAck or timeout.
        def request_status_and_collect(status_list, within:, component: nil, m_id: nil, validate: true)
          validate_ready 'request status'
          component ||= main.c_id
          m_id ||= RSMP::Message.make_m_id

          list = RSMP::StatusList.new(status_list)

          # additional items can be used when verifying the response,
          # but must be removed from the request
          request_list = list.map { |item| item.slice('sCI', 'n') }

          message = RSMP::StatusRequest.new({
                                              'cId' => component,
                                              'sS' => request_list,
                                              'mId' => m_id
                                            })
          apply_nts_message_attributes message
          collector = StatusCollector.new(self, list.to_a, timeout: within, m_id: m_id)
          send_message_and_collect(message, collector, validate: validate)[:collector]
        end

        def process_status_response(message)
          component = find_component message.attribute('cId')
          component.store_status message
          log "Received #{message.type}", message: message, level: :log
          acknowledge message
        end

        def ensure_subscription_path(component_id, code, name)
          @status_subscriptions[component_id] ||= {}
          @status_subscriptions[component_id][code] ||= {}
          @status_subscriptions[component_id][code][name] ||= {}
        end

        def update_subscription(component_id, subscribe_list)
          subscribe_list.each do |item|
            code = item['sCI']
            name = item['n']
            sub = ensure_subscription_path(component_id, code, name)
            sub['uRt'] = item['uRt']
            sub['sOc'] = item['sOc']
          end
        end

        def subscribe_to_status(status_list, component: nil, within: nil, m_id: nil, validate: true)
          validate_ready 'subscribe to status'
          component ||= main.c_id
          m_id ||= RSMP::Message.make_m_id

          list = RSMP::StatusList.new(status_list)
          subscribe_list = list.map { |item| item.slice('sCI', 'n', 'uRt', 'sOc') }

          update_subscription(component, subscribe_list)
          find_component component

          message = RSMP::StatusSubscribe.new({
                                                'cId' => component,
                                                'sS' => subscribe_list,
                                                'mId' => m_id
                                              })
          apply_nts_message_attributes message
          if within
            collector = StatusCollector.new(self, list.to_a, timeout: within, m_id: m_id)
            result = send_message_and_collect message, collector, validate: validate
            result[:collector].ok!
            result
          else
            send_message message, validate: validate
            { sent: message }
          end
        end

        def remove_subscription_item(component_id, code, name)
          return unless @status_subscriptions.dig(component_id, code, name)

          @status_subscriptions[component_id][code].delete name
          @status_subscriptions[component_id].delete(code) if @status_subscriptions[component_id][code].empty?
          @status_subscriptions.delete(component_id) if @status_subscriptions[component_id].empty?
        end

        def unsubscribe_to_status(component_id, status_list, options = {})
          validate_ready 'unsubscribe to status'

          status_list.each do |item|
            remove_subscription_item(component_id, item['sCI'], item['n'])
          end

          message = RSMP::StatusUnsubscribe.new({
                                                  'cId' => component_id,
                                                  'sS' => status_list
                                                })
          apply_nts_message_attributes message
          send_message message, validate: options[:validate]
          message
        end

        # unsubscribes to all statuses (with all attributes) defined in the used SXL
        def unsubscribe_from_all(component_id)
          catalogue = RSMP::Schema.status_catalogue(@sxl, sxl_version)
          status_list = catalogue.flat_map do |status_code_id, names|
            names.map { |name| { 'sCI' => status_code_id.to_s, 'n' => name.to_s } }
          end
          unsubscribe_to_status component_id, status_list
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
