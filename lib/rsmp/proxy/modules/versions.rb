module RSMP
  class Proxy
    module Modules
      # Version negotiation and handling
      # Manages RSMP version handshake between sites and supervisors
      module Versions
        def core_versions
          version = @site_settings['core_version']
          if version == 'latest'
            [RSMP::Schema.latest_core_version]
          elsif version
            [version]
          else
            RSMP::Schema.core_versions
          end
        end

        def core_3_3?
          core_version && version_meets_requirement?(core_version, '>=3.3.0')
        end

        def configured_sxls
          (@site_settings['sxls'] || []).map { |item| item.transform_keys(&:to_s) }
        end

        def primary_configured_sxl
          configured_sxls.first
        end

        def sxl_request_items
          configured_sxls.map do |sxl|
            item = { 'name' => sxl['name'], 'version' => sxl['version'].to_s }
            prefix = RSMP::Schema.sxl_prefix(sxl['name'], sxl['version'], lenient: true)
            item['prefix'] = prefix if prefix
            item
          end
        end

        def check_core_version(message)
          versions = core_versions
          # find versions that both we and the client support
          candidates = message.versions & versions
          if candidates.any?
            @core_version = candidates.max_by { |v| Gem::Version.new(v) } # pick latest version
          else
            reason = "RSMP versions [#{message.versions.join(', ')}] requested, " \
                     "but only [#{versions.join(', ')}] supported."
            dont_acknowledge message, 'Version message rejected', reason, force: true
            raise HandshakeError, reason
          end
        end

        def process_version(message); end

        def extraneous_version(message)
          dont_acknowledge message, 'Received', 'extraneous Version message'
        end

        def send_version(site_id, core_versions)
          send_version_message(site_id, core_versions, step: nil)
        end

        def send_version_request(site_id, core_versions)
          send_version_message(site_id, core_versions, step: 'Request')
        end

        def send_version_response(site_id, core_versions)
          if core_3_3?
            send_message Version.new({
              'step' => 'Response',
              'RSMP' => [{ 'vers' => core_version }],
              'supervisorId' => site_id,
              'SXLS' => version_response_sxls,
              'receiveAlarms' => @site_settings['receive_alarms'] != false
            }), validate: false
          else
            send_version_message(site_id, core_versions, step: nil)
          end
        end

        def send_version_message(site_id, core_versions, step:)
          versions = if core_versions == 'latest'
                       [RSMP::Schema.latest_core_version]
                     elsif core_versions == 'all'
                       RSMP::Schema.core_versions
                     else
                       [core_versions].flatten
                     end
          versions_array = versions.map { |v| { 'vers' => v } }

          site_id_array = [site_id].flatten.map { |id| { 'sId' => id } }
          primary = primary_configured_sxl

          attributes = {
            'RSMP' => versions_array,
            'siteId' => site_id_array
          }
          attributes['SXL'] = primary['version'].to_s if primary
          if step == 'Request'
            attributes['step'] = 'Request'
            attributes['SXLS'] = sxl_request_items
          end

          send_message Version.new(attributes), validate: false
        end

        def version_response_sxls
          accepted_sxls + rejected_sxls
        end

        def version_acknowledged; end

        def component_list_acknowledged; end

        # Use Gem class to check version requirement
        # Requirement must be a string like '1.1', '>=1.0.3' or '<2.1.4',
        # or list of strings, like ['<=1.4','<1.5']
        def self.version_meets_requirement?(version, requirement)
          Gem::Requirement.new(requirement).satisfied_by?(Gem::Version.new(version))
        end

        def version_meets_requirement?(version, requirement)
          RSMP::Proxy::Modules::Versions.version_meets_requirement?(version, requirement)
        end
      end
    end
  end
end
