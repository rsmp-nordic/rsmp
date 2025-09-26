require_relative 'base_options'

module RSMP
  module Options
    # Configuration options specific to RSMP Supervisor instances
    class SupervisorOptions < BaseOptions
      
      # Convenience accessors for commonly used configuration values
      def port
        get('port')
      end

      def port=(value)
        set('port', value)
      end

      def ips
        get('ips')
      end

      def site_id
        get('site_id')
      end

      def guest_settings
        get('guest')
      end

      def sites_settings
        get('sites')
      end

      def core_version
        get('guest.core_version')
      end

      protected

      def defaults
        {
          'port' => 12111,
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
      end

      def schema
        @schema ||= load_schema_file('supervisor_options.json')
      end

      def custom_validations
        errors = []

        return errors unless defined?(RSMP::Schema)

        # Validate guest SXL settings
        guest = get('guest')
        if guest
          sxl = guest['sxl']
          if sxl
            begin
              RSMP::Schema.find_schemas!(sxl)
            rescue RSMP::Schema::UnknownSchemaError => e
              errors << "Invalid guest SXL configuration: #{e.message}"
            end
          end

          # Validate guest core version if specified
          core_ver = guest['core_version']
          if core_ver && !RSMP::Schema.core_versions.include?(core_ver)
            errors << "Unknown guest core version: #{core_ver}. Available versions: #{RSMP::Schema.core_versions.join(', ')}"
          end
        end

        # Validate site-specific SXL settings
        sites = get('sites')
        if sites
          sites.each do |site_id, settings|
            next unless settings

            sxl = settings['sxl']
            if sxl
              begin
                RSMP::Schema.find_schemas!(sxl)
              rescue RSMP::Schema::UnknownSchemaError => e
                errors << "Invalid SXL configuration for site '#{site_id}': #{e.message}"
              end
            else
              errors << "Configuration error for site '#{site_id}': No SXL specified"
            end

            # Validate site core version if specified
            core_ver = settings['core_version']
            if core_ver && !RSMP::Schema.core_versions.include?(core_ver)
              errors << "Unknown core version for site '#{site_id}': #{core_ver}. Available versions: #{RSMP::Schema.core_versions.join(', ')}"
            end
          end
        end

        errors
      end

      private

      def load_schema_file(filename)
        schema_path = File.expand_path("schemas/#{filename}", __dir__)
        if File.exist?(schema_path)
          JSON.parse(File.read(schema_path))
        else
          nil
        end
      end
    end
  end
end