# frozen_string_literal: true

module RSMP
  class SiteProxy < Proxy
    module Modules
      # Handles aggregated status requests and responses
      module AggregatedStatusHandling
        def request_aggregated_status(component, options = {})
          validate_ready 'request aggregated status'
          m_id = options[:m_id] || RSMP::Message.make_m_id
          message = RSMP::AggregatedStatusRequest.new({
                                                        'cId' => component,
                                                        'mId' => m_id
                                                      })
          apply_nts_message_attributes message
          send_and_optionally_collect message, options do |collect_options|
            AggregatedStatusCollector.new(
              self,
              collect_options.merge(task: @task, m_id: m_id, num: 1)
            )
          end
        end

        def validate_aggregated_status(message, status_elements)
          return if status_elements.is_a?(Array) && status_elements.size == 8

          dont_acknowledge message, 'Received', reaons
          raise InvalidMessage
        end

        def process_aggregated_status(message)
          status_elements = message.attribute('se')
          validate_aggregated_status(message, status_elements)
          c_id = message.attributes['cId']
          component = find_component c_id
          unless component
            reason = "component #{c_id} not found"
            dont_acknowledge message, "Ignoring #{message.type}:", reason
            return
          end

          component.aggregated_status_bools = status_elements
          log "Received #{message.type} status for component #{c_id} [#{component.aggregated_status.join(', ')}]",
              message: message
          acknowledge message
        end

        def aggregated_status_changed(component, _options = {})
          @supervisor.aggregated_status_changed self, component
        end
      end
    end
  end
end
