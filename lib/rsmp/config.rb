module RSMP
  # Validation helpers for RSMP runtime configuration hashes and files.
  module Config
    class << self
      def validate(settings = {}, type:, source: nil, log_settings: nil)
        options_class_for(type).new(settings, source: source, log_settings: log_settings)
      end

      def load_file(path, type:)
        raise RSMP::ConfigurationError, 'not found' unless File.exist?(path)
        raise RSMP::ConfigurationError, 'is not a file' unless File.file?(path)
        raise RSMP::ConfigurationError, 'must be a YAML file (.yml or .yaml)' unless yaml_file?(path)

        raw = YAML.load_file(path)
        raise RSMP::ConfigurationError, "Config #{path} must be a hash" unless raw.is_a?(Hash) || raw.nil?

        raw ||= {}
        settings = raw.dup
        log_settings = settings.delete('log') || {}
        validate(settings, type: resolve_type(type, settings), log_settings: log_settings)
      rescue Psych::SyntaxError => e
        raise RSMP::ConfigurationError, "Cannot read config file #{path}: #{e}"
      end

      def types
        %w[site supervisor tlc]
      end

      private

      def yaml_file?(path)
        %w[.yml .yaml].include?(File.extname(path).downcase)
      end

      def resolve_type(type, settings)
        type = type.to_s
        return infer_type(settings) if type == 'auto'

        type
      end

      def infer_type(settings)
        return 'supervisor' if settings.key?('sites')
        return 'site' if settings.key?('supervisors')

        raise RSMP::ConfigurationError, 'Cannot infer config type; use --type site, --type tlc or --type supervisor'
      end

      def options_class_for(type)
        case type.to_s
        when 'site'
          RSMP::Site::Options
        when 'supervisor'
          RSMP::Supervisor::Options
        when 'tlc'
          RSMP::TLC::TrafficControllerSite::Options
        else
          raise RSMP::ConfigurationError, "Unknown config type #{type.inspect}, expected one of #{types.join(', ')}"
        end
      end
    end
  end
end
