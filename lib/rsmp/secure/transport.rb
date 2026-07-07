require 'json'
require 'async/limited_queue'
require 'async/queue'

module RSMP
  module Secure
    # Owns secure frame I/O and exposes a plaintext RSMP message stream.
    class Transport
      MAX_PENDING_INBOUND = 1024
      MAX_PENDING_OUTBOUND = 1024

      Command = Struct.new(:type, :json, :result, keyword_init: true)
      Config = Struct.new(
        :frame_io,
        :role,
        :settings,
        :channel,
        :session_builder,
        :channel_builder,
        :log,
        :parent,
        keyword_init: true
      )
      WriteRequest = Struct.new(:frame, :result, keyword_init: true)

      require_relative 'transport/results'
      require_relative 'transport/rekey'

      include Results
      include Rekey

      attr_reader :settings, :role, :channel

      def initialize(config)
        configure(config)
        initialize_queues
        initialize_rekey_state
      end

      def start
        parent = @parent || Async::Task.current
        @reader = start_task(parent, 'secure reader') { run_reader }
        @writer = start_task(parent, 'secure writer') { run_writer }
        @outbound = start_task(parent, 'secure outbound') { run_outbound }
        @task_parent = parent
        self
      end

      def read_line
        raise_if_failed

        line = @inbound.dequeue
        return line if line

        raise_if_failed
        raise IOError, 'Secure RSMP transport is closed'
      end

      def write_lines(json)
        result = result_queue
        enqueue_command(Command.new(type: :send, json: json, result: result))
        wait_result(result)
      end

      def rekey!
        result = result_queue
        enqueue_command(Command.new(type: :rekey, result: result))
        wait_result(result)
      end

      def close
        fail_transport(IOError.new('Secure RSMP transport is closed'))
        stop_tasks
        @session_builder = nil
        @channel_builder = nil
        @channel = nil
      end

      def log_e2e_up
        log_secure(Secure.handshake_complete_summary(settings, role: role, epoch: @channel.epoch))
      end

      private

      def configure(config)
        @frame_io = config.frame_io
        @role = config.role.to_sym
        @settings = config.settings
        @channel = config.channel
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
        @last_rekey_at = nil
        @data_sent_in_epoch = 0
        @rekeying = false
        @rekey_done = Async::Notification.new
      end

      def start_task(parent, annotation)
        parent.async do |task|
          task.annotate annotation
          yield
        end
      end

      def stop_tasks
        current = Async::Task.current?
        [@reader, @writer, @outbound, @responder_rekey].each do |task|
          task&.stop unless task.equal?(current)
        end
        @reader = nil
        @writer = nil
        @outbound = nil
        @responder_rekey = nil
      end

      def run_reader
        loop do
          frame = @frame_io.read
          case frame['type']
          when 'data'
            enqueue_plaintext(frame)
          when 'rekey'
            process_rekey_frame(frame)
          else
            raise FrameError, "Unexpected secure frame type #{frame['type'].inspect}"
          end
        end
      rescue StandardError => e
        fail_transport(e)
      end

      def run_writer
        while (request = @writes.dequeue)
          write_request(request)
        end
      end

      def write_request(request)
        @frame_io.write(request.frame)
        complete_result(request.result, true)
      rescue StandardError => e
        complete_result(request.result, error: e)
        fail_transport(e)
      end

      def run_outbound
        while (command = @commands.dequeue)
          case command.type
          when :send
            process_send(command)
          when :rekey
            process_rekey_command(command)
          else
            complete_result(command.result, error: FrameError.new("Unknown secure command #{command.type.inspect}"))
          end
        end
      rescue StandardError => e
        fail_transport(e)
      end

      def process_send(command)
        wait_for_rekey
        maybe_rekey!
        attributes = JSON.parse(command.json)
        plaintext = Cbor.encode(attributes)
        write_frame(@channel.encrypt_payload(plaintext))
        @data_sent_in_epoch += 1
        complete_result(command.result, true)
      rescue JSON::ParserError => e
        complete_result(command.result, error: InvalidPacket.new(e.message))
      rescue StandardError => e
        complete_result(command.result, error: e)
        fail_transport(e) if secure_transport_error?(e)
      end

      def process_rekey_command(command)
        unless initiator?
          complete_result(command.result, error: FrameError.new('Secure responder cannot initiate rekey'))
          return
        end

        wait_for_rekey
        execute_rekey_exchange
        complete_result(command.result, true)
      rescue StandardError => e
        complete_result(command.result, error: e)
        fail_transport(e) if secure_transport_error?(e)
      end

      def enqueue_plaintext(frame)
        wait_for_rekey if @rekeying && frame['epoch'] != @channel.epoch
        attributes = Cbor.decode(@channel.decrypt_frame(frame))
        @inbound.enqueue(JSON.generate(attributes, array_nl: nil, object_nl: nil, space_before: nil, space: nil))
      end

      def build_edhoc_session
        @session_builder.call
      end

      def build_channel(session, epoch:, session_id: nil)
        @channel_builder.call(session, epoch: epoch, session_id: session_id)
      end

      def release_edhoc_session(session)
        session.close if session.respond_to?(:close)
      end

      def initiator?
        role == :initiator
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def log_secure(message)
        @log&.call(message, level: :info)
      end
    end
  end
end
