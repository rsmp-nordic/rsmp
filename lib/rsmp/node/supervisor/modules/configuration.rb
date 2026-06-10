module RSMP
  class Supervisor < Node
    module Modules
      # Handles supervisor configuration and site settings
      module Configuration
        def handle_supervisor_settings(supervisor_settings)
          supervisor_settings = denormalize_supervisor_sxls(supervisor_settings || {})
          options = RSMP::Supervisor::Options.new(supervisor_settings || {})
          @supervisor_settings = options.to_h
          @core_version = @supervisor_settings.dig('default', 'core_version')
          check_site_sxls
        end

        def denormalize_supervisor_sxls(settings)
          settings = settings.merge('default' => denormalize_site_sxls(settings['default'])) if settings['default']
          return settings unless settings['sites']

          settings.merge(
            'sites' => settings['sites'].transform_values { |site_settings| denormalize_site_sxls(site_settings) }
          )
        end

        def denormalize_site_sxls(settings)
          sxls = settings['sxls']
          return settings unless sxls.is_a?(Array)

          settings.merge(
            'sxls' => sxls.to_h { |sxl| [sxl['name'], sxl['version']] }
          )
        end

        def check_site_sxls
          sites = @supervisor_settings['sites'].clone || {}
          sites['default'] = @supervisor_settings['default']
          sites.each do |site_id, settings|
            raise RSMP::ConfigurationError, "Configuration for site '#{site_id}' is empty" unless settings

            sxls = settings['sxls']
            raise RSMP::ConfigurationError, "Configuration error for site '#{site_id}': No SXLs specified" unless sxls

            sxls.each do |sxl|
              name = sxl['name']
              if name.to_s == 'core'
                raise RSMP::ConfigurationError,
                      "Configuration error for site '#{site_id}': SXL name cannot be core"
              end

              RSMP::Schema.find_schema! name, sxl['version'], lenient: true
            end
          rescue RSMP::Schema::UnknownSchemaError => e
            raise RSMP::ConfigurationError, "Configuration error for site '#{site_id}': #{e}"
          end
        end

        def site_id_to_site_setting(site_id)
          base = @supervisor_settings['default'] || {}

          return base unless @supervisor_settings['sites']

          site_specific = @supervisor_settings['sites'][site_id] || @supervisor_settings['sites']['default']
          return base unless site_specific

          base.deep_merge(site_specific)
        end

        def ip_to_site_settings(ip)
          @supervisor_settings['sites'][ip] || @supervisor_settings['sites']['default']
        end
      end
    end
  end
end
