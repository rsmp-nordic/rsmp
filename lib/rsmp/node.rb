# Base class for sites and supervisors

module RSMP
  class Node
    include Logging
    include Wait
    include Inspect
    include Task

    attr_reader :archive, :logger, :task, :deferred, :error_queue, :clock, :collector

    def initialize options
      initialize_logging options
      initialize_task
      @deferred = []
      @clock = Clock.new
      @error_queue = Async::Queue.new
      @ignore_errors = []
      @collect = options[:collect]
    end

    # stop proxies, then call super
    def stop_subtasks
      @proxies.each { |proxy| proxy.stop }
      @proxies.clear
      super
    end

    def ignore_errors classes, &block
      was, @ignore_errors = @ignore_errors, [classes].flatten
      yield
    ensure
      @ignore_errors = was
    end

    def notify_error e, options={}
      return if @ignore_errors.find { |klass| e.is_a? klass }
      if options[:level] == :internal
        log ["#{e.to_s} in task: #{Async::Task.current.to_s}",e.backtrace].flatten.join("\n"), level: :error
      end
      @error_queue.enqueue e
    end

    def defer item
      @deferred << item
    end

    def process_deferred
      cloned = @deferred.clone    # clone in case do_deferred restarts the current task
      @deferred.clear
      cloned.each do |item|
        do_deferred item
      end
    end

    def do_deferred item
    end

    def clear_deferred
      @deferred.clear
    end

    def check_required_settings settings, required
      raise ArgumentError.new "Settings is empty" unless settings
      required.each do |setting|
        raise ArgumentError.new "Missing setting: #{setting}" unless settings.include? setting.to_s
      end
    end

    def author
      site_id
    end

  end
end