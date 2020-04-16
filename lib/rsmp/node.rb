# RSMP site
#
# Handles a single connection to a supervisor.
# We connect to the supervisor.

module RSMP
  class Node < Base
    attr_reader :archive, :logger, :task, :deferred

    def initialize options
      super options
      @deferred = []
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

    def start
      starting
      Async do |task|
        task.annotate self.class
        @task = task
        start_action
        idle
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