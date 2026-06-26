module RSMP
  class CLI < Thor
    # Private helpers for loading CLI configuration files.
    module Configuration
      private

      def load_site_configuration
        load_configuration(site_options_class)
      end

      def load_supervisor_configuration
        load_configuration(RSMP::Supervisor::Options)
      end

      def load_configuration(options_class)
        settings = {}
        log_settings = { 'active' => true }
        return [settings, log_settings] unless options[:config]

        options_object = options_class.load_file(options[:config])
        settings = options_object.to_h
        log_settings = log_settings.deep_merge(options_object.log_settings)
        [settings, log_settings]
      rescue RSMP::ConfigurationError => e
        puts "Error: #{e}"
        exit
      end
    end
  end
end
