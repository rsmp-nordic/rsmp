module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # In-memory outgoing communication buffer for site-originated messages.
      module MessageBuffer
        def message_buffer_settings
          @site_settings['message_buffer'] || {}
        end

        def message_buffer_enabled?
          message_buffer_settings['enabled'] != false
        end

        def message_buffer_max_messages
          message_buffer_settings['max_messages'] || 10_000
        end

        def status_buffer_selectors
          return message_buffer_settings['statuses'] if message_buffer_settings.key? 'statuses'

          []
        end

        def status_buffer_selector?(component_id, status)
          selectors = status_buffer_selectors
          return true if selectors == true
          return false unless selectors.is_a?(Array)

          selectors.any? { |selector| status_buffer_selector_matches?(selector, component_id, status) }
        end

        def status_buffer_selector_matches?(selector, component_id, status)
          selector = selector.transform_keys(&:to_s)
          component_matches = !selector['cId'] || selector['cId'] == component_id
          code_matches = !selector['sCI'] || selector['sCI'] == status['sCI']
          name_matches = !selector['n'] || selector['n'] == status['n']
          component_matches && code_matches && name_matches
        end

        def clone_message(message, attributes = message.attributes)
          message.class.new(JSON.parse(JSON.generate(attributes)))
        end

        def site_originated_buffer_candidate?(message)
          message.is_a?(RSMP::AggregatedStatus) ||
            message.is_a?(RSMP::AlarmIssue) ||
            message.is_a?(RSMP::AlarmSuspended) ||
            message.is_a?(RSMP::AlarmResumed) ||
            message.is_a?(RSMP::AlarmAcknowledged) ||
            message.is_a?(RSMP::StatusUpdate)
        end

        def prepare_status_update_for_buffer(message, core_version:, for_send:)
          attributes = JSON.parse(JSON.generate(message.attributes))
          component_id = attributes['cId']
          attributes['sS'] = attributes['sS'].select { |status| status_buffer_selector?(component_id, status) }
          return if attributes['sS'].empty?

          if for_send && core_version && version_meets_requirement?(core_version, '>=3.2.0')
            attributes['sS'].each { |status| status['q'] = 'old' }
          end
          clone_message message, attributes
        end

        def normalize_aggregated_status_buffer(states, core_version)
          if version_meets_requirement?(core_version, '<=3.1.2')
            states.map { |item| item == true || item.to_s == 'true' ? 'true' : 'false' }
          else
            states.map { |item| item == true || item.to_s == 'true' }
          end
        end

        def prepare_aggregated_status_for_buffer(message, core_version:, for_send:)
          attributes = JSON.parse(JSON.generate(message.attributes))
          if for_send && core_version && attributes['se']
            attributes['se'] = normalize_aggregated_status_buffer(attributes['se'], core_version)
          end
          clone_message message, attributes
        end

        def prepare_message_for_buffer(message, core_version: @core_version, for_send: false)
          return unless message_buffer_enabled?
          return unless site_originated_buffer_candidate? message
          return false if message.is_a?(RSMP::StatusUpdate) && status_buffer_selectors == false
          return false if message.is_a?(RSMP::Alarm) && !receive_alarms?

          if message.is_a? RSMP::AggregatedStatus
            prepare_aggregated_status_for_buffer message, core_version: core_version, for_send: for_send
          elsif message.is_a? RSMP::StatusUpdate
            prepare_status_update_for_buffer message, core_version: core_version, for_send: for_send
          else
            clone_message message
          end
        end

        def buffer_message(message, error = nil)
          prepared = prepare_message_for_buffer message, core_version: @core_version
          if prepared
            enqueue_buffered_message prepared
          elsif site_originated_buffer_candidate? message
            log "Discarded #{message.type}; it is not configured for buffering", message: message, level: :warning
          else
            super
          end
        rescue NotReady, IOError
          raise error if error
        end

        def enqueue_buffered_message(message)
          while @message_buffer.size >= message_buffer_max_messages
            dropped = @message_buffer.shift
            log "Dropped buffered #{dropped.type}; message buffer is full", message: dropped, level: :warning
          end
          @message_buffer << message
          log "Buffered #{message.type}; #{message_buffer.size} message(s) queued", message: message, level: :warning
          message
        end

        def flush_message_buffer
          return if @message_buffer.empty?

          queued = @message_buffer
          @message_buffer = []
          log "Sending #{queued.size} buffered message(s)", level: :info
          queued.each_with_index do |message, index|
            break unless flush_buffered_message(message, queued, index)
          end
        end

        def flush_buffered_message(message, queued, index)
          prepared = prepare_message_for_buffer message, core_version: @core_version, for_send: true
          return true unless prepared

          send_message prepared, 'from buffer', buffer: false
          true
        rescue NotReady, IOError
          @message_buffer = queued[index..] + @message_buffer
          log "Stopped sending buffered messages; #{message_buffer.size} message(s) remain queued", level: :warning
          false
        end
      end
    end
  end
end
