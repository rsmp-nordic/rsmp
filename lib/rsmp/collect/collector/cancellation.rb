module RSMP
  class Collector
    # An error occurred upstream.
    # Check if we should cancel.
    def receive_error(error, options = {})
      case error
      when RSMP::SchemaError
        receive_schema_error error, options
      when RSMP::DisconnectError
        receive_disconnect error, options
      end
    end

    # Cancel if we received a schema error for a message type we're collecting
    def receive_schema_error(error, options)
      return unless @options.dig(:cancel, :schema_error)

      message = options[:message]
      return unless message

      klass = message.class.name.split('::').last
      return unless @filter&.type.nil? || [@filter&.type].flatten.include?(klass)

      @distributor.log "#{identifier}: cancelled due to schema error in #{klass} #{message.m_id_short}", level: :debug
      cancel error
    end

    # Cancel if we received a notification about a disconnect
    def receive_disconnect(error, _options)
      return unless @options.dig(:cancel, :disconnect)

      @distributor.log "#{identifier}: cancelled due to a connection error: #{error}", level: :debug
      cancel error
    end

    # Abort collection
    def cancel(error = nil)
      @error = error
      @status = :cancelled
      do_stop
    end
  end
end
