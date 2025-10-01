module RSMP
  module ProxyExtensions
    module ConnectionManagement
      # close connection, but keep our main task running so we can reconnect
      def close
        log 'Closing connection', level: :warning
        close_stream
        close_socket
        stop_reader
        change_state :disconnected
        distribute_error DisconnectError.new('Connection was closed')

        # stop timer
        # as we're running inside the timer, code after stop_timer() will not be called,
        # unless it's in the ensure block
        stop_timer
      end

      def stop_subtasks
        stop_timer
        stop_reader
        clear
        super
      end

      def stop_timer
        @timer&.stop
      ensure
        @timer = nil
      end

      def stop_reader
        @reader&.stop
      ensure
        @reader = nil
      end

      def close_stream
        @stream&.close
      ensure
        @stream = nil
      end

      def close_socket
        @socket&.close
      ensure
        @socket = nil
      end

      def stop_task
        close
        super
      end
    end
  end
end
