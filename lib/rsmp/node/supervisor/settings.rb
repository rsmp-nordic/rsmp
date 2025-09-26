module RSMP
  module SupervisorExtensions
    module Settings
      def site_id
        @supervisor_settings['site_id']
      end

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
    end
  end
end
