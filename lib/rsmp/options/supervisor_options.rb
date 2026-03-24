module RSMP
  class Supervisor < Node
    # Configuration options for supervisors.
    class Options < RSMP::Options
      def defaults
        {
          'port' => 12_111,
          'ips' => 'all',
          'default' => {
            'sxl' => 'tlc',
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
    end
  end
end
