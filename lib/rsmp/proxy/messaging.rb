module RSMP
  module ProxyExtensions
    module OutgoingMessages
      def send_message(message, reason = nil, validate: true, force: false)
        ensure_can_send!(force)
        prepare_outgoing_message(message, validate)
        transmit_message(message)
        post_send_success(message, reason)
      rescue IOError
        buffer_message message
      rescue SchemaError, RSMP::Schema::Error => e
        handle_schema_error(message, e)
      end

      def buffer_message(message)
        # TODO
        # log "Cannot send #{message.type} because the connection is closed.", message: message, level: :error
      end

      def log_send(message, reason = nil)
        str = if reason
                "Sent #{message.type} #{reason}"
              else
                "Sent #{message.type}"
              end

        if message.type == 'MessageNotAck'
          log str, message: message, level: :warning
        else
          log str, message: message, level: :log
        end
      end

      def send_and_optionally_collect(message, options)
        collect_options = options[:collect] || options[:collect!]
        if collect_options
          task = @task.async do |task|
            task.annotate 'send_and_optionally_collect'
            collector = yield collect_options     # call block to create collector
            collector.collect
            collector.ok! if options[:collect!]   # raise any errors if the bang version was specified
            collector
          end

          send_message message, validate: options[:validate]
          { sent: message, collector: task.wait }
        else
          send_message message, validate: options[:validate]
          { sent: message }
        end
      end

      def assign_nts_message_attributes(message)
        message.attributes['ntsOId'] = main && main.ntsoid ? main.ntsoid : ''
        message.attributes['xNId'] = main && main.xnid ? main.xnid : ''
      end

      private

      def ensure_can_send!(force)
        raise NotReady if !force && !connected?
        raise IOError unless @protocol
      end

      def prepare_outgoing_message(message, validate)
        message.direction = :out
        message.generate_json
        message.validate(schemas) unless validate == false
      end

      def transmit_message(message)
        @protocol.write_lines message.json
      end

      def post_send_success(message, reason)
        expect_acknowledgement message
        distribute message
        log_send message, reason
      end

      def handle_schema_error(message, error)
        schemas = Array(error.schemas)
        schemas_string = schemas.map { |schema| "#{schema.first}: #{schema.last}" }.join(', ')
        str = "Could not send #{message.type} because schema validation failed (#{schemas_string}): #{error.message}"
        log str, message: message, level: :error
        distribute_error error.exception("#{str} #{message.json}")
      end
    end

    module IncomingMessages
      def should_validate_ingoing_message?(message)
        return true unless @site_settings

        skip = @site_settings['skip_validation']
        return true unless skip

        klass = message.class.name.split('::').last
        !skip.include?(klass)
      end

      def process_deferred
        @node.process_deferred
      end

      def expect_version_message(message)
        return if message.is_a?(Version) || message.is_a?(MessageAck) || message.is_a?(MessageNotAck)

        raise HandshakeError, 'Version must be received first'
      end

      def verify_sequence(message)
        expect_version_message(message) unless @version_determined
      end

      def process_packet(json)
        attributes = parse_message_attributes(json)
        message = build_incoming_message(attributes, json)
        handle_incoming_message(message)
        message
      rescue InvalidPacket => e
        handle_invalid_packet(e, json)
      rescue MalformedMessage => e
        handle_malformed_message(e, attributes)
      rescue SchemaError, RSMP::Schema::Error => e
        handle_incoming_schema_error(message, e)
      rescue InvalidMessage => e
        handle_invalid_message(message, e)
      rescue FatalError => e
        handle_fatal_message(message, e)
      ensure
        @node.clear_deferred
      end

      def process_message(message)
        case message
        when MessageAck
          process_ack message
        when MessageNotAck
          process_not_ack message
        when Version
          process_version message
        when RSMP::Watchdog
          process_watchdog message
        else
          dont_acknowledge message, 'Received', "unknown message (#{message.type})"
        end
      end

      def will_not_handle(message, reason = nil)
        reason ||= "since we're a #{self.class.name.downcase}"
        log "Ignoring #{message.type}, #{reason}", message: message, level: :warning
        dont_acknowledge message, nil, reason
      end

      def process_watchdog(message)
        log "Received #{message.type}", message: message, level: :log
        @latest_watchdog_received = Clock.now
        acknowledge message
      end
    end

    module IncomingHandlers
      private

      def parse_message_attributes(json)
        Message.parse_attributes json
      end

      def build_incoming_message(attributes, json)
        message = Message.build attributes, json
        validate_incoming_message message
        verify_sequence message
        message
      end

      def validate_incoming_message(message)
        message.validate(schemas) if should_validate_ingoing_message?(message)
      end

      def handle_incoming_message(message)
        with_deferred_distribution do
          distribute message
          process_message message
        end
        process_deferred
      end

      def handle_invalid_packet(error, json)
        str = "Received invalid package, must be valid JSON but got #{json.size} bytes: #{error.message}"
        distribute_error error.exception(str)
        log str, level: :warning
        nil
      end

      def handle_malformed_message(error, attributes)
        str = "Received malformed message, #{error.message}"
        distribute_error error.exception(str)
        malformed = Malformed.new(attributes || {})
        log str, message: malformed, level: :warning
        nil
      end

      def handle_incoming_schema_error(message, error)
        schemas = Array(error.schemas)
        schemas_string = schemas.map { |schema| "#{schema.first}: #{schema.last}" }.join(', ')
        reason = "schema errors (#{schemas_string}): #{error.message}"
        str = "Received invalid #{message.type}"
        distribute_error error.exception(str), message: message
        dont_acknowledge message, str, reason
        message
      end

      def handle_invalid_message(message, error)
        reason = error.message.to_s
        str = "Received invalid #{message.type},"
        distribute_error error.exception("#{str} #{message.json}"), message: message
        dont_acknowledge message, str, reason
        message
      end

      def handle_fatal_message(message, error)
        reason = error.message
        str = "Rejected #{message.type},"
        distribute_error error.exception(str), message: message
        dont_acknowledge message, str, reason
        close
        message
      end
    end

    module Acknowledgements
      def expect_acknowledgement(message)
        return if message.is_a?(MessageAck) || message.is_a?(MessageNotAck)

        @awaiting_acknowledgement[message.m_id] = message
      end

      def dont_expect_acknowledgement(message)
        @awaiting_acknowledgement.delete message.attribute('oMId')
      end

      def acknowledge(original)
        raise InvalidArgument unless original

        ack = MessageAck.build_from(original)
        ack.original = original.clone
        send_message ack, "for #{ack.original.type} #{original.m_id_short}"
        check_ingoing_acknowledged original
      end

      def dont_acknowledge(original, prefix = nil, reason = nil, force: true)
        raise InvalidArgument unless original

        str = [prefix, reason].join(' ')
        log str, message: original, level: :warning if reason
        message = MessageNotAck.new({
                                      'oMId' => original.m_id,
                                      'rea' => reason || 'Unknown reason'
                                    })
        message.original = original.clone
        send_message message, "for #{original.type} #{original.m_id_short}", force: force
      end

      def find_original_for_message(message)
        @awaiting_acknowledgement[message.attribute('oMId')]
      end

      def check_outgoing_acknowledged(message)
        return if @outgoing_acknowledged[message.type]

        @outgoing_acknowledged[message.type] = true
        acknowledged_first_outgoing message
      end

      def check_ingoing_acknowledged(message)
        return if @ingoing_acknowledged[message.type]

        @ingoing_acknowledged[message.type] = true
        acknowledged_first_ingoing message
      end

      def acknowledged_first_outgoing(message); end

      def acknowledged_first_ingoing(message); end

      def process_ack(message)
        original = find_original_for_message message
        if original
          dont_expect_acknowledgement message
          message.original = original
          log_acknowledgement_for_original message, original

          case original.type
          when 'Version'
            version_acknowledged
          when 'StatusSubscribe'
            status_subscribe_acknowledged original
          end

          check_outgoing_acknowledged original

          @acknowledgements[original.m_id] = message
          @acknowledgement_condition.signal message
        else
          log_acknowledgement_for_unknown message
        end
      end

      def process_not_ack(message)
        original = find_original_for_message message
        if original
          dont_expect_acknowledgement message
          message.original = original
          log_acknowledgement_for_original message, original
          @acknowledgements[original.m_id] = message
          @acknowledgement_condition.signal message
        else
          log_acknowledgement_for_unknown message
        end
      end

      def log_acknowledgement_for_original(message, original)
        str = "Received #{message.type} for #{original.type} #{message.attribute('oMId')[0..3]}"
        if message.type == 'MessageNotAck'
          reason = message.attributes['rea']
          str = "#{str}: #{reason}" if reason
          log str, message: message, level: :warning
        else
          log str, message: message, level: :log
        end
      end

      def log_acknowledgement_for_unknown(message)
        log(
          "Received #{message.type} for unknown message #{message.attribute('oMId')[0..3]}",
          message: message,
          level: :warning
        )
      end

      def status_subscribe_acknowledged(original)
        component = find_component original.attribute('cId')
        return unless component

        short = Message.shorten_m_id original.m_id
        subscribe_list = original.attributes['sS']
        log "StatusSubscribe #{short} acknowledged, allowing repeated status values for #{subscribe_list}", level: :info
        component.allow_repeat_updates subscribe_list
      end
    end

    module VersionNegotiation
      def core_versions
        version = @site_settings['core_version']
        if version == 'latest'
          [RSMP::Schema.latest_core_version]
        elsif version
          [version]
        else
          RSMP::Schema.core_versions
        end
      end

      def check_core_version(message)
        versions = core_versions
        candidates = message.versions & versions
        if candidates.any?
          @core_version = candidates.max_by { |v| Gem::Version.new(v) }
        else
          reason = "RSMP versions [#{message.versions.join(', ')}] requested, " \
                   "but only [#{versions.join(', ')}] supported."
          dont_acknowledge message, 'Version message rejected', reason, force: true
          raise HandshakeError, reason
        end
      end

      def process_version(message); end

      def extraneous_version(message)
        dont_acknowledge message, 'Received', 'extraneous Version message'
      end

      def handshake_complete
        change_state :ready
      end

      def version_acknowledged; end
    end

    module StateSynchronization
      def wait_for_state(state, timeout:)
        states = [state].flatten
        return if states.include?(@state)

        wait_for_condition(@state_condition, timeout: timeout) do
          states.include?(@state)
        end
        @state
      rescue RSMP::TimeoutError
        raise RSMP::TimeoutError, "Did not reach state #{state} within #{timeout}s"
      end

      def send_version(site_id, core_versions)
        versions = if core_versions == 'latest'
                     [RSMP::Schema.latest_core_version]
                   elsif core_versions == 'all'
                     RSMP::Schema.core_versions
                   else
                     [core_versions].flatten
                   end
        versions_array = versions.map { |v| { 'vers' => v } }

        site_id_array = [site_id].flatten.map { |id| { 'sId' => id } }

        version_response = Version.new({
                                         'RSMP' => versions_array,
                                         'siteId' => site_id_array,
                                         'SXL' => sxl_version.to_s
                                       })
        send_message version_response
      end
    end
  end
end
