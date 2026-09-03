module RSMP
  # Base class for sites and supervisors.
  class Node
    include Logging
    include Task
    include EventSource

    attr_reader :archive, :logger, :task, :deferred, :clock, :collector

    def initialize(options = {})
      initialize_logging options
      initialize_task
      initialize_event_source
      @deferred = []
      @clock = Clock.new
      @collect = options[:collect]
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
