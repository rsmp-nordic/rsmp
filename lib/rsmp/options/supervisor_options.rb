module RSMP
  class Supervisor < Node
    # Configuration options for supervisors.
    class Options < RSMP::Options
      def defaults
        {
          'port' => 12_111,
          'connection_role' => 'server',
          'ips' => 'all',
          'default' => {
            'sxls' => {
              'tlc' => RSMP::Schema.latest_version(:tlc)
            },
            'intervals' => {
              'timer' => 1,
              'watchdog' => 1
            },
            'timeouts' => {
              'watchdog' => 2,
              'acknowledgement' => 2,
              'command' => 10,
              'status_response' => 10
            }
          }
        }
      end

      def schema_file
        'supervisor.json'
      end

      private

      def validate_effective!(config)
        base = config['default'] || {}
        sites = (config['sites'] || {}).transform_values { |settings| base.deep_merge(settings) }
        effective = config.merge('sites' => sites)
        validate!(effective, path: File.join(SCHEMAS_PATH, 'required_supervisor_settings.json'))
      end
    end
  end
end
