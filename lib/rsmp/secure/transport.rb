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
        :peer_id,
        :session_builder,
        :channel_builder,
        :log,
        :parent,
        keyword_init: true
      )
      WriteRequest = Struct.new(:frame, :result, keyword_init: true)

      require_relative 'transport/results'
      require_relative 'transport/rekey'
      require_relative 'transport/lifecycle'

      include Results
      include Rekey
      include Lifecycle

      attr_reader :settings, :role, :channel

      def initialize(config)
        configure(config)
        initialize_queues
        initialize_rekey_state
      end

      def start
        parent = @parent || Async::Task.current
        @task_parent = parent
        @reader = start_task(parent, 'secure reader') { run_reader }
        @writer = start_task(parent, 'secure writer') { run_writer }
        @outbound = start_task(parent, 'secure outbound') { run_outbound }
        @rekey_monitor = start_task(parent, 'secure rekey monitor') { run_rekey_monitor }
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
        fail_transport(IOError.new('Secure RSMP transport is closed'), log_failure: false)
        stop_tasks
        @session_builder = nil
        @channel_builder = nil
        @pending_rekey_channel&.clear!
        @channel&.clear!
        @pending_rekey_channel = nil
        @channel = nil
      end

      def log_secure_channel_up
        log_secure(Secure.channel_up_summary(settings, role: role, epoch: @channel.epoch, peer_id: @peer_id))
      end

      private

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
      rescue EOFError => e
        # EOF before a new frame is an ordinary peer disconnect. Preserve it
        # as the transport failure so blocked readers and writers wake up, but
        # do not report it as a malformed or failed secure channel.
        fail_transport(e, log_failure: false)
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
          when :peer_rekey, :threshold_rekey
            process_internal_rekey_command(command)
          else
            complete_result(command.result, error: FrameError.new("Unknown secure command #{command.type.inspect}"))
          end
        end
      rescue StandardError => e
        fail_transport(e)
      end

      def process_send(command)
        resolve_pending_rekey_before_send
        renew_if_due!
        attributes = JSON.parse(command.json)
        plaintext = Cbor.encode(attributes)
        write_frame(@channel.encrypt_payload(plaintext))
        renew_if_due!
        complete_result(command.result, true)
      rescue JSON::ParserError => e
        complete_result(command.result, error: InvalidPacket.new(e.message))
      rescue StandardError => e
        complete_result(command.result, error: e)
        fail_transport(e) if secure_transport_error?(e)
      end

      def process_rekey_command(command)
        wait_for_rekey
        initiator? ? execute_rekey_exchange : request_rekey_and_wait
        complete_result(command.result, true)
      rescue StandardError => e
        complete_result(command.result, error: e)
        fail_transport(e) if secure_transport_error?(e)
      end

      def process_internal_rekey_command(command)
        @rekey_command_queued = false
        unless @rekey_requested || rekey_due?
          complete_result(command.result, true)
          return
        end
        wait_for_rekey unless @rekey_requested
        initiator? ? execute_rekey_exchange : request_rekey_and_wait
        complete_result(command.result, true)
      rescue StandardError => e
        complete_result(command.result, error: e)
        fail_transport(e)
      end

      def enqueue_plaintext(frame)
        if @rekeying || @rekey_requested
          raise FrameError, 'Application data is not permitted while secure rekey is required or in progress'
        end

        attributes = Cbor.decode(@channel.decrypt_frame(frame))
        @inbound.enqueue(JSON.generate(attributes, array_nl: nil, object_nl: nil, space_before: nil, space: nil))
        schedule_rekey_if_due
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
