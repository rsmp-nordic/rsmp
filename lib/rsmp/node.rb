# RSMP site
#
# Handles a single connection to a supervisor.
# We connect to the supervisor.

module RSMP
  class Node < Base
    attr_reader :archive, :logger, :task

    def initialize options
      super options
    end

    def start
      starting
      Async do |task|
        task.annotate self.class
        @task = task
        start_action
      end
    rescue Errno::EADDRINUSE => e
      log "Cannot start: #{e.to_s}", level: :error
    rescue SystemExit, SignalException, Interrupt
      @logger.unmute_all
      exiting
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