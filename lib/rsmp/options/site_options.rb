require_relative 'base_options'

module RSMP
  module Options
    # Configuration options specific to RSMP Site instances
    class SiteOptions < BaseOptions
      
      def initialize(config = {})
        # Handle the special case where main component should be replaced, not merged
        normalized_config = normalize_config_input(config)
        if normalized_config.dig('components', 'main')
          # Store the main component to replace defaults
          @custom_main_component = normalized_config['components']['main']
        end
        
        super(config)
      end
      
      # Convenience accessors for commonly used configuration values
      def site_id
        get('site_id')
      end

      def site_id=(value)
        set('site_id', value)
      end

      def supervisors
        get('supervisors')
      end

      def supervisors=(value)
        set('supervisors', value)
      end

      def sxl
        get('sxl')
      end

      def sxl_version
        get('sxl_version')
      end

      def core_version
        get('core_version')
      end

      def components
        get('components')
      end

      def intervals
        get('intervals')
      end

      def timeouts
        get('timeouts')
      end

      def send_after_connect?
        get('send_after_connect')
      end

      protected

      def defaults
        {
          'site_id' => 'RN+SI0001',
          'supervisors' => [
            { 'ip' => '127.0.0.1', 'port' => 12111 }
          ],
          'sxl' => 'tlc',
          'sxl_version' => default_sxl_version,
          'intervals' => {
            'timer' => 0.1,
            'watchdog' => 1,
            'reconnect' => 0.1
          },
          'timeouts' => {
            'watchdog' => 2,
            'acknowledgement' => 2
          },
          'send_after_connect' => true,
          'components' => {
            'main' => @custom_main_component || { 'C1' => {} }
          }
        }
      end

      def schema
        @schema ||= load_schema_file('site_options.json')
      end

      def custom_validations
        errors = []

        return errors unless defined?(RSMP::Schema)

        # Validate SXL and version compatibility
        sxl_type = get('sxl')
        sxl_ver = get('sxl_version')
        if sxl_type && sxl_ver
          begin
            RSMP::Schema.find_schema!(sxl_type, sxl_ver.to_s, lenient: true)
          rescue RSMP::Schema::UnknownSchemaError => e
            errors << "Invalid SXL configuration: #{e.message}"
          end
        end

        # Validate core version if specified
        core_ver = get('core_version')
        if core_ver && !RSMP::Schema.core_versions.include?(core_ver)
          errors << "Unknown core version: #{core_ver}. Available versions: #{RSMP::Schema.core_versions.join(', ')}"
        end

        # Validate components structure
        components = get('components')
        if components && !components.key?('main')
          errors << "Components must include a 'main' component"
        end

        errors
      end

      private

      def normalize_config_input(config)
        case config
        when Hash
          config
        when String
          if File.exist?(config)
            require 'yaml'
            YAML.load_file(config)
          else
            raise ConfigurationError, "Configuration file not found: #{config}"
          end
        else
          raise ConfigurationError, "Invalid configuration type: #{config.class}"
        end
      end

      def default_sxl_version
        return RSMP::Schema.latest_version(:tlc) if defined?(RSMP::Schema)
        '1.2.1'
      end

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