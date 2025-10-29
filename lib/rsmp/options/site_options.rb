module RSMP
  class Site < Node
    # Configuration options for sites.
    class Options < RSMP::Options
      def defaults
        {
          'site_id' => 'RN+SI0001',
          'supervisors' => [
            { 'ip' => '127.0.0.1', 'port' => 12_111 }
          ],
          'sxl' => 'tlc',
          'sxl_version' => RSMP::Schema.latest_version(:tlc),
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
            'main' => {
              'C1' => {}
            }
          }
        }
      end

      def schema_file
        'site.json'
      end

      private

      def apply_defaults(options)
        defaults = defaults()
        defaults['components']['main'] = options['components']['main'] if options.dig('components', 'main')
        defaults.deep_merge(options)
      end
    end
  end
end
