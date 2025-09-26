module RSMP
  module SupervisorProxyExtensions
    module Status
      def process_status_request(message, options = {})
        component_id = message.attributes['cId']
        ss = build_status_response(component_id, message)

        response = StatusResponse.new({
                                        'cId' => component_id,
                                        'sTs' => clock.to_s,
                                        'sS' => ss,
                                        'mId' => options[:m_id]
                                      })

        assign_nts_message_attributes response
        acknowledge message
        send_message response
      end

      def rsmpify_value(value, quality)
        if value.is_a?(Array) || value.is_a?(Set)
          value
        elsif %w[undefined unknown].include?(quality.to_s)
          nil
        else
          value.to_s
        end
      end

      private

      def build_status_response(component_id, message)
        component = @site.find_component component_id
        message.attributes['sS'].map do |arg|
          value, quality = component.get_status arg['sCI'], arg['n'], { sxl_version: sxl_version }
          build_status_entry(arg, value, quality)
        end
      rescue UnknownComponent
        handle_unknown_status_component message, component_id
      end

      def build_status_entry(arg, value, quality)
        { 's' => rsmpify_value(value, quality), 'q' => quality.to_s }.merge arg
      end

      def handle_unknown_status_component(message, component_id)
        log "Received #{message.type} with unknown component id '#{component_id}' and cannot infer type",
            message: message, level: :warning
        message.attributes['sS'].map do |arg|
          arg.dup.merge('q' => 'undefined', 's' => nil)
        end
      end
    end
  end
end
