module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Optional testing convention, not RSMP Core SXL negotiation.
      module SxlHints
        def start_handshake
          @sxls = configured_sxls
          @accepted_sxls = @sxls.dup
          @rejected_sxls = []
          send_version_request @site_settings['site_id'], advertised_core_versions
        end

        def configured_sxls
          selections = @site.hinted_sxl_versions(@ip, @port)
          super.map do |item|
            version = selections[item['name']]
            item['versions']&.include?(version) ? item.merge('version' => version) : item
          end
        end

        def process_not_ack(message)
          original = find_original_for_message(message)
          initial = original.is_a?(Version) && original.m_id == @initial_version_request_id && !@version_determined
          super
          return unless initial

          legacy = original.versions.all? { |version| version_meets_requirement?(version, '<3.3.0') }
          apply_sxl_hint(message.attributes['rea']) if legacy
          close(reason: :version_rejected)
        end

        def apply_sxl_hint(reason)
          version = parse_sxl_hint(reason)
          return unless version

          configured = primary_configured_sxl
          return unless configured && configured['versions']&.include?(version)
          return if configured['version'] == version

          name = configured['name']
          @site.hinted_sxl_versions(@ip, @port)[name] = version
          # Subscriptions and queued messages belong to the previous SXL version.
          @status_subscriptions.clear
          @message_buffer.clear
          log "Following testing SXL hint: #{name} #{version} on next connection", level: :info
        end

        def parse_sxl_hint(reason)
          return unless reason.is_a?(String)

          hints = reason.scan(/\bhint:\s*([^\s;]+)/).flatten
          return unless hints.size == 1

          version = hints.first
          version if RSMP::Schema.strict_version?(version)
        end
      end
    end
  end
end
