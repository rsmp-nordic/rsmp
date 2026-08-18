module RSMP
  # Base class for sites and supervisors.
  class Node
    include Logging
    include Task

    attr_reader :archive, :logger, :task, :deferred, :error_queue, :clock, :collector,
                :secure_connection_rate_limiter, :secure_revocation_list

    def initialize(options = {})
      initialize_logging options
      initialize_task
      @deferred = []
      @clock = Clock.new
      @error_queue = Async::Queue.new
      @ignore_errors = []
      @collect = options[:collect]
      @secure_connection_rate_limiter = Secure::ConnectionRateLimiter.new
      @secure_revocation_list = Secure::RevocationList.new
    end

    def inspect
      "#<#{self.class.name}:#{object_id} id: #{site_id}}>"
    end

    def now
      clock.now
    end

    # stop proxies, then call super
    def stop_subtasks
      @proxies.each(&:stop)
      @proxies.clear
      super
    end

    def ignore_errors(classes)
      was = @ignore_errors
      @ignore_errors = [classes].flatten
      yield
    ensure
      @ignore_errors = was
    end

    def distribute_error(error, options = {})
      return if @ignore_errors.find { |klass| error.is_a? klass }

      if options[:level] == :internal
        log ["#{error} in task: #{Async::Task.current}", error.backtrace].flatten.join("\n"),
            level: :error
      end
      @error_queue.enqueue error
    end

    def defer(key, item = nil)
      @deferred << [key, item]
    end

    def process_deferred
      cloned = @deferred.clone # clone in case do_deferred restarts the current task
      @deferred.clear
      cloned.each do |pair|
        do_deferred pair.first, pair.last
      end
    end

    def do_deferred(key, item = nil); end

    def clear_deferred
      @deferred.clear
    end

    def revoke_secure_credential!(credential_id)
      secure_revocation_list.revoke(credential_id)
      closed = Array(@proxies).count do |proxy|
        peer_id = proxy.secure_peer_credential_id
        next false unless peer_id && secure_revocation_list.revoked?(peer_id)

        proxy.close
        true
      end
      log "Revoked secure credential #{credential_id.inspect}; closed #{closed} active connection(s)", level: :warning
      closed
    end

    def restore_secure_credential!(credential_id)
      restored = secure_revocation_list.restore(credential_id)
      log "Restored secure credential #{credential_id.inspect} for new connections", level: :info if restored
      restored
    end

    def check_required_settings(settings, required)
      raise ArgumentError, 'Settings is empty' unless settings

      required.each do |setting|
        raise ArgumentError, "Missing setting: #{setting}" unless settings.include? setting.to_s
      end
    end

    def author
      site_id
    end
  end
end
