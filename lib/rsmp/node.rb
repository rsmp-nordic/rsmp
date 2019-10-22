# RSMP site
#
# Handles a single connection to a supervisor.
# We connect to the supervisor.

module RSMP
  class Node
    attr_reader :archive, :logger

    def initialize options
      @archive = options[:archive] || RSMP::Archive.new
      @logger = options[:logger] || RSMP::Logger.new(options[:log_settings]) 
    end

    def start
      starting
      Async do |task|
        task.annotate self.class
        @task = task
        start_action
      end
    rescue Errno::EADDRINUSE => e
      log str: "Cannot start: #{e.to_s}", level: :error
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

    def log item
      @logger.log item
    end

    def exiting
      log str: "Exiting", level: :info
    end

    def check_required_settings settings, required
      raise ArgumentError.new "Settings is empty" unless settings
      required.each do |setting|
        raise ArgumentError.new "Missing setting: #{setting}" unless settings.include? setting.to_s
      end 
    end

    def wait_for condition, timeout, &block
      @task.with_timeout(timeout) do |task|
        loop do
          value = yield condition.wait
          return value if value
        end
      end
    end   
  end
end