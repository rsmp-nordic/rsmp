module RSMP
  module Secure
    class Transport
      # Task, queue, and connection-state lifecycle for the secure transport.
      module Lifecycle
        private

        def configure(config)
          @frame_io = config.frame_io
          @role = config.role.to_sym
          @settings = config.settings
          @channel = config.channel
          @peer_id = config.peer_id
          @session_builder = config.session_builder
          @channel_builder = config.channel_builder
          @log = config.log
          @parent = config.parent
        end

        def initialize_queues
          @inbound = Async::LimitedQueue.new(MAX_PENDING_INBOUND)
          @commands = Async::LimitedQueue.new(MAX_PENDING_OUTBOUND)
          @writes = Async::LimitedQueue.new(MAX_PENDING_OUTBOUND)
          @rekey_responses = Async::Queue.new
          @pending_results = []
          @error = nil
        end

        def initialize_rekey_state
          @epoch_started_at = monotonic_now
          @rekeying = false
          @rekey_requested = false
          @rekey_command_queued = false
          @pending_rekey_channel = nil
          @rekey_done = Async::Notification.new
          @epoch_changed = Async::Notification.new
        end

        def start_task(parent, annotation)
          parent.async do |task|
            task.annotate annotation
            yield
          end
        end

        def stop_tasks
          current = Async::Task.current?
          [@reader, @writer, @outbound, @responder_rekey, @rekey_monitor].each do |task|
            task&.stop unless task.equal?(current)
          end
          @reader = nil
          @writer = nil
          @outbound = nil
          @responder_rekey = nil
          @rekey_monitor = nil
        end
      end
    end
  end
end
