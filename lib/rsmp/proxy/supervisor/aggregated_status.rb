module RSMP
  module SupervisorProxyExtensions
    module AggregatedStatus
      def send_all_aggregated_status
        @site.components.each_pair do |_c_id, component|
          send_aggregated_status component if component.grouped
        end
      end

      def send_aggregated_status(component, options = {})
        m_id = options[:m_id] || RSMP::Message.make_m_id

        se = aggregated_status_elements(component)

        message = AggregatedStatus.new({
                                         'aSTS' => clock.to_s,
                                         'cId' => component.c_id,
                                         'fP' => nil,
                                         'fS' => nil,
                                         'se' => se,
                                         'mId' => m_id
                                       })

        assign_nts_message_attributes message
        send_and_optionally_collect message, options do |collect_options|
          Collector.new self, collect_options.merge(task: @task, type: 'MessageAck')
        end
      end

      def process_aggregated_status_request(message)
        log "Received #{message.type}", message: message, level: :log
        component = find_component(message)
        acknowledge message
        send_aggregated_status component
      end

      def process_aggregated_status(message)
        se = message.attribute('se')
        validate_aggregated_status(message, se)
        on = set_aggregated_status se
        log "Received #{message.type} status [#{on.join(', ')}]", message: message, level: :log
        acknowledge message
      end

      private

      def aggregated_status_elements(component)
        if Proxy.version_meets_requirement?(core_version, '<=3.1.2')
          component.aggregated_status_bools.map { |bool| bool ? 'true' : 'false' }
        else
          component.aggregated_status_bools
        end
      end

      def find_component(message)
        component_id = message.attributes['cId']
        @site.find_component component_id
      end
    end
  end
end
