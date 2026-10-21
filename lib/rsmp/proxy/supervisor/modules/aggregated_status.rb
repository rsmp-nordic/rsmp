module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Handles aggregated status messages
      module AggregatedStatus
        def send_component_list
          components = @site.component_list
          result = send_generated_message ComponentList.new('components' => components)
          @last_component_list = JSON.parse(JSON.generate(components)) if result.success?
          result
        end

        def synchronize_site_state
          send_component_list if @site.component_list != @last_component_list
          send_changed_site_status
        end

        def component_list_acknowledged
          return if ready? || @initial_aggregated_status_id

          @initial_aggregated_status_id = Message.make_m_id
          send_aggregated_status(nil, m_id: @initial_aggregated_status_id)
        end

        def initial_status_acknowledged(original)
          return unless core_3_3_0_or_newer? && original.m_id == @initial_aggregated_status_id

          @initial_aggregated_status_id = nil
          handshake_complete unless ready?
        end

        def send_all_aggregated_status
          return send_site_aggregated_status if core_3_3_0_or_newer?

          @site.components.each_pair do |_c_id, component|
            send_aggregated_status component if component.grouped
          end
        end

        # Send aggregated status for a component
        def send_aggregated_status(component = nil, m_id: nil)
          return send_site_aggregated_status(m_id: m_id) if core_3_3_0_or_newer?

          m_id ||= RSMP::Message.make_m_id

          se = if core_version && Proxy.version_meets_requirement?(core_version, '<=3.1.2')
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
          send_generated_message message
        end

        def send_changed_site_status
          bits = @site.site_aggregated_status
          return if bits == @last_site_status
          return if connected? && !ready?

          result = send_site_aggregated_status
          @last_site_status = bits if result.success?
          result
        end

        def send_site_aggregated_status(m_id: nil)
          message = RSMP::AggregatedStatus.new(
            'mId' => m_id, 'aSTS' => clock.to_s, 'se' => @site.site_aggregated_status
          )
          apply_nts_message_attributes message
          result = send_generated_message message
          @last_site_status = message.attributes['se'].dup if result.success?
          result
        end

        def process_aggregated_status_request(message)
          log "Received #{message.type}", message: message, level: :log
          if core_3_3_0_or_newer?
            acknowledge message
            return send_site_aggregated_status
          end

          component_id = message.attributes['cId']
          component = @site.find_component component_id
          acknowledge message
          send_aggregated_status component
        end
      end
    end
  end
end
