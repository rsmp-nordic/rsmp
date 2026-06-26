module RSMP
  class Site < Node
    # Configuration options for sites.
    class Options < RSMP::Options
      def defaults
        {
          'site_id' => 'RN+SI0001',
          'connection_role' => 'client',
          'ip' => '0.0.0.0',
          'supervisors' => default_supervisors,
          'sxls' => default_sxls,
          'intervals' => default_intervals,
          'timeouts' => default_timeouts,
          'send_after_connect' => true,
          'message_buffer' => default_message_buffer,
          'components' => default_components
        }
      end

      def schema_file
        'site.json'
      end

      private

      def default_message_buffer
        {
          'max_messages' => 10_000,
          'statuses' => true
        }
      end

      def default_supervisors
        [{ 'ip' => '127.0.0.1', 'port' => 12_111 }]
      end

      def default_sxls
        { 'tlc' => RSMP::Schema.latest_version(:tlc) }
      end

      def default_intervals
        { 'timer' => 0.1, 'watchdog' => 1, 'reconnect' => 0.1 }
      end

      def default_timeouts
        { 'watchdog' => 2, 'acknowledgement' => 2 }
      end

      def default_components
        { 'main' => { 'C1' => {} } }
      end

      def apply_defaults(options)
        defaults = defaults()
        defaults['components']['main'] = options['components']['main'] if options.dig('components', 'main')
        data = defaults.deep_merge(options)
        data['port'] ||= data.dig('supervisors', 0, 'port')
        data
      end
    end
  end
end
