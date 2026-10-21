module RSMP
  class SiteProxy < Proxy
    module Modules
      # Handles aggregated status requests and responses
      module AggregatedStatus
        # Build and send an AggregatedStatusRequest. Returns Result<AggregatedStatusRequest>.
        def request_aggregated_status(component = nil, m_id: nil, validate: true)
          readiness = validate_ready 'request aggregated status'
          return readiness if readiness.failure?

          m_id ||= RSMP::Message.make_m_id
          message = RSMP::AggregatedStatusRequest.new({
                                                        'cId' => component,
                                                        'mId' => m_id
                                                      })
          message.attributes.delete('cId') if core_3_3_0_or_newer?
          apply_nts_message_attributes message
          send_message(message, validate: validate).map(&:message)
        end

        def request_aggregated_status!(...)
          request_aggregated_status(...).value!
        end

        # Build, send an AggregatedStatusRequest and collect the response. Returns Result<Exchange>.
        def request_aggregated_status_and_collect(component = nil, within:, m_id: nil, validate: true)
          readiness = validate_ready 'request aggregated status'
          return readiness if readiness.failure?

          m_id ||= RSMP::Message.make_m_id
          message = RSMP::AggregatedStatusRequest.new({
                                                        'cId' => component,
                                                        'mId' => m_id
                                                      })
          message.attributes.delete('cId') if core_3_3_0_or_newer?
          apply_nts_message_attributes message
          collector = AggregatedStatusCollector.new(self, timeout: within, m_id: m_id, num: 1)
          send_message_and_collect(message, collector, validate: validate)
        end

        def request_aggregated_status_and_collect!(...)
          request_aggregated_status_and_collect(...).value!
        end

        def validate_aggregated_status(message, status_elements)
          return if status_elements.is_a?(Array) && status_elements.size == 8

          dont_acknowledge message, 'Received', reaons
          raise InvalidMessage
        end

        def process_aggregated_status(message)
          return process_site_aggregated_status(message) if core_3_3_0_or_newer?

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

        def process_site_aggregated_status(message)
          @site_aggregated_status = message.attribute('se').dup.freeze
          acknowledge message
          @supervisor.site_aggregated_status_changed(self)
          complete_initial_status(message)
        end

        attr_reader :site_aggregated_status

        def complete_initial_status(message)
          return unless core_3_3_0_or_newer? && !ready? && @component_list_received && @outgoing_watchdog_acknowledged
          return unless message.is_a?(RSMP::AggregatedStatus)

          handshake_complete
        end

        def aggregated_status_changed(component, _options = {})
          @supervisor.aggregated_status_changed self, component
        end
      end
    end
  end
end
