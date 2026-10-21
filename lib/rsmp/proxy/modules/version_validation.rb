module RSMP
  class Proxy
    module Modules
      # Shape and cross-message constraints for version negotiation.
      module VersionValidation
        def validate_version_array!(message)
          items = message.attributes['RSMP']
          valid = items.is_a?(Array) && !items.empty? && items.all? do |item|
            item.is_a?(Hash) && item['vers'].is_a?(String) &&
              (RSMP::Schema.strict_version?(item['vers']) || RSMP::Schema.normalize_core_version(item['vers']))
          end
          raise HandshakeError, 'Invalid RSMP version array' unless valid
        end

        def validate_version!(message, step:)
          validation = message.validate(core: core_version)
          raise HandshakeError, validation.message if validation.invalid?
          return unless core_3_3_0_or_newer?

          raise HandshakeError, "Expected Version #{step}" unless message.step == step

          validate_sxl_names!(message.sxls)
          validate_primary_sxl!(message) if step == 'Request'
        end

        def validate_sxl_names!(items)
          names = items.map { |item| item['name'] }
          raise HandshakeError, 'Duplicate SXL names' unless names.uniq == names

          items.each do |item|
            version = item['version']
            if version && !RSMP::Schema.strict_version?(version)
              raise HandshakeError, 'SXL version must use MAJOR.MINOR.PATCH'
            end
          end
        end

        def validate_primary_sxl!(message)
          primary = message.attributes['SXL']
          return unless primary && !primary.empty? && message.sxls.none? { |item| item['version'] == primary }

          raise HandshakeError, 'Primary SXL version does not match SXLS'
        end

        def validate_sxl_response!(sxls)
          offered = sxl_request_items
          names = offered.map { |item| item['name'] }
          returned = sxls.reject { |item| item['status'] == 'expected' }.map { |item| item['name'] }
          raise HandshakeError, 'SXLS must report every offered SXL exactly once' unless returned.sort == names.sort

          sxls.each { |item| validate_sxl_status!(item, names) }
        end

        def validate_sxl_status!(item, names)
          case item['status']
          when 'ok'
            raise HandshakeError, 'SXL version must match the request exactly' unless valid_sxl_response?(item)
          when 'expected'
            raise HandshakeError, 'Expected SXL was offered' if names.include?(item['name'])
          when 'mismatch'
            supported = item['supported']
            unless supported == supported.sort_by { |version| Gem::Version.new(version) }
              raise HandshakeError, 'Supported SXL versions must be sorted'
            end
          end
        end

        def valid_sxl_response?(accepted)
          requested = sxl_request_items.find { |item| item['name'] == accepted['name'] }
          RSMP::Schema.strict_version?(accepted['version']) && requested &&
            requested['version'] == accepted['version']
        end
      end
    end
  end
end
