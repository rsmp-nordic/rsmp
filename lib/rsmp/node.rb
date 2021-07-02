# Base class for sites and supervisors

module RSMP
  class Node
    include Logging
    include Wait
    include Inspect

    attr_reader :archive, :logger, :task, :deferred, :error_queue, :clock

    def initialize options
      initialize_logging options
      @task = options[:task]
      @deferred = []
      @clock = Clock.new
      @error_queue = Async::Queue.new
    end

    def notify_error e, options={}
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

    def do_start task
      task.annotate self.class.to_s
      @task = task
      start_action
      idle
    end

    def start
      starting
      if @task
        do_start @task
      else
        Async do |task|
          do_start task
        end
      end
    rescue Errno::EADDRINUSE => e
      log "Cannot start: #{e.to_s}", level: :error
    rescue SystemExit, SignalException, Interrupt
      @logger.unmute_all
      exiting
    end

    def idle
      loop do
        @task.sleep 60
      end
    end

    def stop
      @task.stop if @task
    end

    def restart
      stop
      start
    end

    def exiting
      log "Exiting", level: :info
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