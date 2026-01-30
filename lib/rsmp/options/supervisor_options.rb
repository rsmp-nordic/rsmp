module RSMP
  class Supervisor < Node
    # Configuration options for supervisors.
    class Options < RSMP::Options
      def defaults
        {
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
      end

      def schema_file
        'supervisor.json'
      end
    end
  end
end
