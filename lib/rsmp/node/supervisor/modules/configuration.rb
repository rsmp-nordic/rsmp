# frozen_string_literal: true

module RSMP
  class Supervisor < Node
    module Modules
      # Handles supervisor configuration and site settings
      module Configuration
        def handle_supervisor_settings(supervisor_settings)
          defaults = {
            'port' => 12_111,
            'ips' => 'all',
            'guest' => {
              'sxl' => 'tlc',
              'intervals' => {
                'timer' => 1,
                'watchdog' => 1
              },
              'timeouts' => {
                'watchdog' => 2,
                'acknowledgement' => 2
              }
            }
          }

          # merge options into defaults
          @supervisor_settings = defaults.deep_merge(supervisor_settings)
          @core_version = @supervisor_settings['guest']['core_version']
          check_site_sxl_types
        end

        def check_site_sxl_types
          sites = @supervisor_settings['sites'].clone || {}
          sites['guest'] = @supervisor_settings['guest']
          sites.each do |site_id, settings|
            raise RSMP::ConfigurationError, "Configuration for site '#{site_id}' is empty" unless settings

            sxl = settings['sxl']
            raise RSMP::ConfigurationError, "Configuration error for site '#{site_id}': No SXL specified" unless sxl

            RSMP::Schema.find_schemas! sxl if sxl
          rescue RSMP::Schema::UnknownSchemaError => e
            raise RSMP::ConfigurationError, "Configuration error for site '#{site_id}': #{e}"
          end
        end

        def site_id_to_site_setting(site_id)
          return {} unless @supervisor_settings['sites']

          @supervisor_settings['sites'].each_pair do |id, settings|
            return settings if id == 'guest' || id == site_id
          end
          raise HandshakeError, "site id #{site_id} unknown"
        end

        def ip_to_site_settings(ip)
          @supervisor_settings['sites'][ip] || @supervisor_settings['sites']['guest']
        end
      end
    end
  end
end
