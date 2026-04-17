module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Handles aggregated status messages
      module AggregatedStatus
        def send_all_aggregated_status
          @site.components.each_pair do |_c_id, component|
            send_aggregated_status component if component.grouped
          end
        end

        # Send aggregated status for a component
        def send_aggregated_status(component, m_id: nil)
          m_id ||= RSMP::Message.make_m_id

          se = if Proxy.version_meets_requirement?(core_version, '<=3.1.2')
                 component.aggregated_status_bools.map { |bool| bool ? 'true' : 'false' }
               else
                 component.aggregated_status_bools
               end

          message = RSMP::AggregatedStatus.new({
                                                 'aSTS' => clock.to_s,
                                                 'cId' => component.c_id,
                                                 'fP' => nil,
                                                 'fS' => nil,
                                                 'se' => se,
                                                 'mId' => m_id
                                               })

          apply_nts_message_attributes message
          send_message message
        end

        def process_aggregated_status_request(message)
          log "Received #{message.type}", message: message, level: :log
          component_id = message.attributes['cId']
          component = @site.find_component component_id
          acknowledge message
          send_aggregated_status component
        end
      end
    end
  end
end
