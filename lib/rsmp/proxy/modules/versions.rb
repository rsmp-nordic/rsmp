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
          elsif version.nil? || version == 'all'
            RSMP::Schema.core_versions
          else
            [RSMP::Schema.normalize_core_version(version)].compact
          end
        end

        # Version strings to advertise before a Core version has been selected.
        # Include known legacy spellings so peers using exact string matching
        # can find a common pre-3.3 version.
        def advertised_core_versions
          versions = core_versions.flat_map { |version| wire_core_version_aliases(version) }
          configured = @site_settings['core_version']
          versions.unshift configured if RSMP::Schema.normalize_core_version(configured)
          versions.uniq
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
            version = RSMP::Schema.sanitize_version(sxl['version'].to_s)
            item = { 'name' => sxl['name'], 'version' => version }
            prefix = RSMP::Schema.sxl_prefix(sxl['name'], version)
            item['prefix'] = prefix if prefix
            item
          end
        end

        def check_core_version(message)
          versions = core_versions
          candidates = message.versions.filter_map do |wire_version|
            normalized = RSMP::Schema.normalize_core_version(wire_version)
            [wire_version, normalized] if normalized && versions.include?(normalized)
          end
          if candidates.any?
            @core_version_string, @core_version = candidates.max_by do |_wire_version, normalized|
              Gem::Version.new(normalized)
            end
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
            send_generated_message Version.new({
                                                 'step' => 'Response',
                                                 'RSMP' => [{ 'vers' => core_version }],
                                                 'supervisorId' => site_id,
                                                 'SXLS' => version_response_sxls,
                                                 'receiveAlarms' => @site_settings['receive_alarms'] != false
                                               }), validate: false
          else
            send_legacy_version_response(site_id, core_versions)
          end
        end

        def send_legacy_version_response(site_id, core_versions)
          response_versions = normalized_core_versions(core_versions).map do |version|
            normalized = RSMP::Schema.normalize_core_version(version)
            normalized == core_version ? core_version_string : version
          end.uniq
          attributes = version_message_attributes(site_id, response_versions)
          primary = accepted_sxls.first
          attributes['SXL'] = primary['version'].to_s if primary
          send_message Version.new(attributes), validate: false
        end

        def send_version_message(site_id, core_versions, step:)
          attributes = version_message_attributes(site_id, core_versions)
          attributes.merge!(version_request_attributes) if step == 'Request'
          send_generated_message Version.new(attributes), validate: false
        end

        def version_message_attributes(site_id, core_versions)
          primary = primary_configured_sxl
          attributes = {
            'RSMP' => version_items(core_versions),
            'siteId' => site_id_items(site_id)
          }
          attributes['SXL'] = primary['version'].to_s if primary
          attributes
        end

        def version_items(core_versions)
          normalized_core_versions(core_versions).map { |version| { 'vers' => version } }
        end

        def normalized_core_versions(core_versions)
          case core_versions
          when 'latest'
            [RSMP::Schema.latest_core_version]
          when 'all'
            RSMP::Schema.core_versions
          else
            [core_versions].flatten
          end
        end

        def wire_core_version_aliases(version)
          normalized = RSMP::Schema.normalize_core_version(version)
          return [version] unless normalized
          return [normalized] if Gem::Version.new(normalized) >= Gem::Version.new('3.3.0')
          return [normalized] unless normalized.end_with?('.0')

          [normalized, normalized.delete_suffix('.0')]
        end

        def site_id_items(site_id)
          [site_id].flatten.map { |id| { 'sId' => id } }
        end

        def version_request_attributes
          {
            'step' => 'Request',
            'SXLS' => sxl_request_items
          }
        end

        def version_response_sxls
          accepted_sxls + rejected_sxls
        end

        def validate_sxl_response!(sxls)
          invalid = sxls.find { |accepted| !valid_sxl_response?(accepted) }
          return unless invalid

          raise HandshakeError,
                "Invalid SXL version #{invalid['name']} #{invalid['version']}; " \
                'Core 3.3 requires an exact MAJOR.MINOR.PATCH match'
        end

        def valid_sxl_response?(accepted)
          requested = sxl_request_items.find { |item| item['name'] == accepted['name'] }
          RSMP::Schema.strict_version?(accepted['version']) && requested &&
            requested['version'] == accepted['version']
        end

        def version_acknowledged; end

        def component_list_acknowledged; end

        # Use Gem class to check version requirement
        # Requirement must be a string like '1.1.0', '>=1.0.3' or '<2.1.4',
        # or list of strings, like ['<=1.4.0','<1.5.0']
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
